// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

/// `main` runs this before anything reads secure storage. A loss has to reach
/// the release log level, and nothing it does may stop the app starting.
void main() {
  late _MockStorage storage;
  late Logger log;
  late List<LogRecord> records;

  setUp(() {
    storage = _MockStorage();
    hierarchicalLoggingEnabled = true;
    log = Logger.detached('upgrade-test')..level = Level.ALL;
    records = [];
    log.onRecord.listen(records.add);
  });

  test('a loss is logged at WARNING, so release builds keep it', () async {
    const lost = SecureStorageUpgradeStatus(
      state: SecureStorageUpgradeState.legacyDataUnreadable,
      entryCount: 1,
      willDiscardOnNextAccess: true,
    );
    when(() => storage.checkUpgradeStatus()).thenAnswer((_) async => lost);

    final status = await logSecureStorageUpgradeStatus(storage, log);

    expect(status, same(lost));
    expect(records.single.level, Level.WARNING);
    expect(records.single.message, contains('legacyDataUnreadable'));
  });

  test('an intact store is only INFO', () async {
    const ok = SecureStorageUpgradeStatus(
      state: SecureStorageUpgradeState.ok,
    );
    when(() => storage.checkUpgradeStatus()).thenAnswer((_) async => ok);

    await logSecureStorageUpgradeStatus(storage, log);

    expect(records.single.level, Level.INFO);
  });

  test('a failing check is logged and swallowed, never thrown', () async {
    when(() => storage.checkUpgradeStatus())
        .thenThrow(StateError('channel gone'));

    final status = await logSecureStorageUpgradeStatus(storage, log);

    expect(status, isNull);
    expect(records.single.level, Level.WARNING);
    // The type, as at every other log site, and never the exception's text.
    expect(records.single.message, contains('StateError'));
    expect(records.single.message, isNot(contains('channel gone')));
  });
}
