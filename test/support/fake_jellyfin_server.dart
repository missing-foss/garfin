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
  _Reply? _fallback;

  /// Queues one reply for `path`. Queued replies are consumed in order, so a
  /// test can script "not approved, not approved, approved".
  void on(
    String path, {
    Object? json,
    int status = 200,
    DioExceptionType? failWith,
  }) {
    _script
        .putIfAbsent(path, () => <_Reply>[])
        .add(_Reply(json: json, status: status, failWith: failWith));
  }

  /// The reply for any path with nothing queued.
  void fallback({Object? json, int status = 200}) {
    _fallback = _Reply(json: json, status: status);
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

    final queued = _script[options.path];
    final reply = (queued != null && queued.isNotEmpty)
        ? (queued.length == 1 ? queued.first : queued.removeAt(0))
        : _fallback;

    if (reply == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: options, statusCode: 404),
      );
    }

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

class _Reply {
  _Reply({this.json, this.status = 200, this.failWith});

  final Object? json;
  final int status;
  final DioExceptionType? failWith;
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
