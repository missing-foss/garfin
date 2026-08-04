// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:developer' as developer;

import 'package:logging/logging.dart';

/// Garfin's root logger. Everything logs through this, never through `print` —
/// the no-`print` gate in `dev/verify.sh` enforces that, and `dart:developer`'s
/// `log` keeps output on the debug channel rather than stdout.
final Logger log = Logger('garfin');

/// Wire the `logging` package to the debug channel. Call once from `main`.
///
/// Release builds stay at [Level.WARNING]: Garfin handles an admin token and a
/// Quick Connect secret, and the less that reaches a device log the better.
void configureLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    developer.log(
      redactSecrets(record.message),
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error == null ? null : redactSecrets('${record.error}'),
      stackTrace: record.stackTrace,
    );
  });
}

/// Strips credential-bearing query values out of anything on its way to a log.
///
/// The Quick Connect exchange puts the `Secret` in a **query string**
/// (`GET /QuickConnect/Connect?secret=…`), so a `DioException` carries it in
/// `requestOptions.uri` and prints it in `toString()`. Logging that error
/// verbatim would write a live credential to the device log — the one thing
/// `docs/JELLYFIN-API.md` is most explicit about.
///
/// The access token is covered in all three shapes it actually takes, not just
/// the query one: `?api_key=…`, the `Token="…"` inside the `Authorization`
/// header, and `{"AccessToken":"…"}` in the body of `AuthenticateByName` and
/// `AuthenticateWithQuickConnect`. The last is the one worth naming — it is a
/// live admin token, and a response body is the shape a leak has.
///
/// This is a backstop, not the primary defence: [redactSecrets] runs on every
/// record, and the client layer converts Dio errors into `JellyfinException`
/// rather than passing them on. Two independent guards, because a leaked
/// credential is not something to protect with one.
String redactSecrets(String input) => input.replaceAllMapped(
      // Groups: 1 the quote around the name (or none), 2 the name,
      // 3 the separator, 4 the quote around the value (or none).
      //
      // Both separators matter. `=` catches the query-string form,
      // `?secret=…`, which is how the secret goes *out*. `:` catches the JSON
      // form, which is how it comes *back*: measured on 10.11.11, the response
      // body of that same endpoint is
      // `{"Authenticated":false,"Secret":"DA4C…","Code":"793600"}`. A pattern
      // that only knew about `=` would pass a logged response body through
      // untouched, which is the shape a leak would actually have.
      //
      // `accesstoken` / `access_token` covers the *other* body this app sees:
      // `POST /Users/AuthenticateByName` answers
      // `{"AccessToken":"988dc…","ServerId":"…"}`, and that is a live admin
      // token. Bare `token` is in the list for the header form,
      // `Authorization: MediaBrowser Token="…"`. The `(?<![\w-])` lookbehind is
      // what keeps `token` from matching inside `AccessToken` and producing a
      // half-redacted mess.
      RegExp(
        r'''(?<![\w-])(["']?)(secret|api_key|apikey|access_?token|'''
        r'''x-emby-token|token|pw|password)'''
        r'''\1\s*([=:])\s*(["']?)[^&\s,"'`)\]}]*\4''',
        caseSensitive: false,
      ),
      (m) => '${m[1]}${m[2]}${m[1]}${m[3]}${m[4]}REDACTED${m[4]}',
    );
