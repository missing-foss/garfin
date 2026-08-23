// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scripted Jellyfin, plugged in where dio's transport would be.
///
/// Tests drive the real `JellyfinApi` — interceptor, query building, parsing
/// and error mapping — rather than a stub of it, because that is the layer the
/// ground rules actually live in.
class FakeJellyfinServer implements HttpClientAdapter {
  FakeJellyfinServer();

  /// Every request that reached the transport, in order. Assertions about the
  /// `Authorization` header read from here.
  final List<RequestOptions> requests = <RequestOptions>[];

  final Map<String, List<_Reply>> _script = <String, List<_Reply>>{};
  final List<_Matcher> _matchers = <_Matcher>[];
  _Reply? _fallback;

  /// Queues one reply for `path`. Queued replies are consumed in order, so a
  /// test can script "not approved, not approved, approved".
  void on(
    String path, {
    Object? json,
    int status = 200,
    DioExceptionType? failWith,
    Duration? delay,
  }) {
    _script.putIfAbsent(path, () => <_Reply>[]).add(
        _Reply(json: json, status: status, failWith: failWith, delay: delay));
  }

  /// Queues a reply matched on the **query** as well as the path, and reused
  /// for every request that matches.
  ///
  /// [on] is positional: replies are consumed in order and the last one queued
  /// answers everything after it. That is right for scripting a sequence — "not
  /// approved, not approved, approved" — and wrong when several unrelated
  /// questions share a path. `/Items` carries the grid's page, the visibility
  /// lookup, the tagged count and the last-item warning, so a test scripting
  /// two of them positionally is one provider rebuild away from handing the
  /// page's answer to the count. That has produced a *plausible* wrong number
  /// in three different tests rather than an error, which is the species
  /// `docs/JELLYFIN-API.md` names at the top: a harness answering confidently.
  ///
  /// Matchers are checked before the positional script, newest first, so a
  /// later registration can change one answer — the server having gained a tag
  /// between two reads — without re-scripting the rest.
  void onQuery(
    String path,
    bool Function(Map<String, dynamic> query) where, {
    Object? json,
    int status = 200,
    DioExceptionType? failWith,
    Duration? delay,
  }) {
    _matchers.insert(
      0,
      _Matcher(
        path: path,
        where: where,
        reply: _Reply(
            json: json, status: status, failWith: failWith, delay: delay),
      ),
    );
  }

  /// The reply for any path with nothing queued.
  ///
  /// [delay] makes a scripted call take measurable time, which is the only way
  /// to tell a bounded-parallel batch from a serial loop: both make the same
  /// requests, in the same order, and differ only in when.
  void fallback({
    Object? json,
    int status = 200,
    Duration? delay,
    DioExceptionType? failWith,
  }) {
    _fallback =
        _Reply(json: json, status: status, delay: delay, failWith: failWith);
  }

  int callsTo(String path) =>
      requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    _Reply? reply;
    for (final matcher in _matchers) {
      if (matcher.path == options.path &&
          matcher.where(options.queryParameters)) {
        reply = matcher.reply;
        break;
      }
    }

    if (reply == null) {
      final queued = _script[options.path];
      reply = (queued != null && queued.isNotEmpty)
          ? (queued.length == 1 ? queued.first : queued.removeAt(0))
          : _fallback;
    }

    if (reply == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: options, statusCode: 404),
      );
    }

    if (reply.delay != null) await Future<void>.delayed(reply.delay!);

    if (reply.failWith != null) {
      throw DioException(requestOptions: options, type: reply.failWith!);
    }

    return ResponseBody.fromString(
      jsonEncode(reply.json),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Matcher {
  _Matcher({required this.path, required this.where, required this.reply});

  final String path;
  final bool Function(Map<String, dynamic> query) where;
  final _Reply reply;
}

class _Reply {
  _Reply({this.json, this.status = 200, this.failWith, this.delay});

  final Object? json;
  final int status;
  final DioExceptionType? failWith;
  final Duration? delay;
}

/// A Jellyfin user DTO, with only the fields sign-in reads.
Map<String, dynamic> userJson({
  String id = 'user-1',
  String name = 'Alex',
  bool isAdministrator = true,
}) =>
    {
      'Id': id,
      'Name': name,
      'Policy': {
        'IsAdministrator': isAdministrator,
        'IsDisabled': false,
      },
    };

/// An `AuthenticationResult` DTO.
Map<String, dynamic> authResultJson({
  String token = 'token-abc123',
  String name = 'Alex',
  bool isAdministrator = true,
}) =>
    {
      'AccessToken': token,
      'ServerId': 'server-1',
      'User': userJson(name: name, isAdministrator: isAdministrator),
    };
