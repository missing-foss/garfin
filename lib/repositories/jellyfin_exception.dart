// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';

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

  /// 403. Authenticated but not allowed — normally the non-admin case, which
  /// sign-in is supposed to catch first (ground rule 7).
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
  const JellyfinException(this.kind, {this.message, this.detail});

  final JellyfinErrorKind kind;
  final String? message;

  /// A value the UI may show as part of a localised sentence — the account name
  /// for [JellyfinErrorKind.notAdministrator], the server address for
  /// [JellyfinErrorKind.unreachable]. Never anything secret.
  final String? detail;

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
}
