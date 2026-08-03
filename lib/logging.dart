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
/// `docs/JELLYFIN-API.md` is most explicit about. `api_key` gets the same
/// treatment because Jellyfin accepts the access token that way too.
///
/// This is a backstop, not the primary defence: [redactSecrets] runs on every
/// record, and the client layer converts Dio errors into `JellyfinException`
/// rather than passing them on. Two independent guards, because a leaked
/// credential is not something to protect with one.
String redactSecrets(String input) => input.replaceAllMapped(
      RegExp(
        r'\b(secret|api_key|apikey|x-emby-token|pw|password)=([^&\s"'
        r"'`)\]}]*)",
        caseSensitive: false,
      ),
      (m) => '${m[1]}=REDACTED',
    );
