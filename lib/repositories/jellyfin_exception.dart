// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../logging.dart';

/// Why a call failed, in terms the UI can turn into one plain sentence.
///
/// The UI switches on this exhaustively rather than showing server text.
/// Jellyfin's error bodies are English, untranslated, and occasionally a stack
/// trace — none of which belongs in front of a parent, and one of which
/// (`docs/JELLYFIN-API.md`, the bricked-detail-endpoint case) is a raw
/// `System.ArgumentNullException`.
enum JellyfinErrorKind {
  /// No route to the server: wrong address, wrong network, server down.
  unreachable,

  /// A route, but no answer in time.
  timeout,

  /// 401. Credentials wrong, or a stored token the server no longer honours.
  unauthorized,

  /// 403. Authenticated but not allowed.
  ///
  /// Rarer than it sounds: measured on 10.11.11, a non-admin token is *not*
  /// refused with a 403 on the reads Garfin does, which is why ground rule 7 is
  /// enforced at sign-in rather than left to surface here.
  forbidden,

  /// 404. Usually a URL that reaches *something* which is not Jellyfin.
  notFound,

  /// 5xx, or a response that did not parse.
  server,

  /// Quick Connect is switched off server-side.
  quickConnectUnavailable,

  /// The code was never approved inside the polling window.
  quickConnectExpired,

  /// Ground rule 7: the account authenticated, but it is not an administrator.
  notAdministrator,

  /// The request was cancelled — a dispose, or a user backing out.
  cancelled,
}

/// A failure from the Jellyfin layer, already stripped of anything sensitive.
///
/// [message] is for the log, never for the screen. It never contains a token,
/// a password or a Quick Connect secret: the constructors below build it from
/// the status code and the request *path*, deliberately not `uri`, which for
/// `GET /QuickConnect/Connect?secret=…` would carry a live credential.
class JellyfinException implements Exception {
  const JellyfinException(
    this.kind, {
    this.message,
    this.detail,
    this.diagnostic,
  });

  final JellyfinErrorKind kind;
  final String? message;

  /// A value the UI may show as part of a localised sentence — the account name
  /// for [JellyfinErrorKind.notAdministrator], the server address for
  /// [JellyfinErrorKind.unreachable]. Never anything secret.
  final String? detail;

  /// The client-side cause, in a form that can go on screen.
  ///
  /// "Garfin couldn't reach your server" is the right *sentence*, but it is the
  /// same sentence for a wrong address, a phone on the wrong network, a VPN
  /// swallowing the LAN, and a platform permission that was never granted.
  /// Found the hard way: an unreachable-server report took three guesses to
  /// diagnose because every cause collapsed into one message.
  ///
  /// This is deliberately **not** server text — no response body, no status
  /// line, nothing Jellyfin wrote. It is dio's exception type plus the
  /// underlying Dart error, which is a bounded set of client-side values:
  /// `connectionError · SocketException: … errno = 13, Permission denied`.
  /// It still goes through [redactSecrets] on the way out, because a
  /// `SocketException` carries the address it failed on and the rule is that
  /// nothing reaches a screen or a log unscrubbed.
  final String? diagnostic;

  /// Maps a `DioException` onto a [kind], keeping nothing that could carry a
  /// credential.
  factory JellyfinException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final where = error.requestOptions.path;

    final kind = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      // dio's own decode step running long. Rare, but it is still "no answer in
      // time" from where the user is sitting.
      DioExceptionType.transformTimeout =>
        JellyfinErrorKind.timeout,
      DioExceptionType.cancel => JellyfinErrorKind.cancelled,
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        JellyfinErrorKind.unreachable,
      DioExceptionType.badCertificate => JellyfinErrorKind.unreachable,
      DioExceptionType.badResponse => switch (status) {
          401 => JellyfinErrorKind.unauthorized,
          403 => JellyfinErrorKind.forbidden,
          404 => JellyfinErrorKind.notFound,
          _ => JellyfinErrorKind.server,
        },
    };

    return JellyfinException(
      kind,
      diagnostic: describeCause(error),
      // Path and status only. `error.message` embeds the full URI, and the
      // whole point of not using it is the `?secret=` on the Quick Connect
      // poll.
      message: 'jellyfin call failed: $where'
          '${status == null ? '' : ' (HTTP $status)'}',
    );
  }

  @override
  String toString() => 'JellyfinException(${kind.name})'
      '${message == null ? '' : ': $message'}';

  /// dio's failure type plus the Dart error underneath it, scrubbed.
  ///
  /// The `errno` is the useful part and the reason this exists at all:
  /// `Permission denied` (13) means the platform refused the socket — an
  /// Android 16+ / GrapheneOS local-network restriction, or a revoked network
  /// permission — while `Connection refused` (111) means the address was
  /// reached and nothing was listening, and `No route to host` (113) means the
  /// phone is not on that network. Three completely different fixes behind one
  /// sentence.
  @visibleForTesting
  static String describeCause(DioException error) {
    final buffer = StringBuffer(error.type.name);
    final cause = error.error;
    if (cause != null) {
      buffer.write(' · ${cause.runtimeType}');
      // The **type** of every cause, but the *text* of only these three.
      //
      // `DioException.error` is an arbitrary object, and one of the things it
      // can be is a `FormatException` from a response body that failed to
      // parse — whose `toString()` embeds up to 75 characters of that body.
      // Measured: a proxy's HTML error page comes out as
      //
      //     FormatException: Unexpected character (at character 1)
      //     <html><body><h1>502 Bad Gateway</h1><p>nginx: upstream …
      //
      // which is server text on screen, and an internal hostname with it. This
      // class promises not to do that, so it has to be enforced rather than
      // intended.
      //
      // These three are ours rather than the server's, and they are the only
      // ones carrying an `errno` — which is the entire reason this field
      // exists. Anything else contributes its type and stops there:
      // `unknown · FormatException` still tells the four causes apart.
      if (cause is SocketException ||
          cause is OSError ||
          cause is HandshakeException) {
        buffer.write(': $cause');
      }
    }
    // Bounded, so a pathological message cannot fill the screen.
    final described = redactSecrets(buffer.toString());
    return described.length <= 300 ? described : '${described.substring(0, 300)}…';
  }
}
