// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/app_info.dart';
import 'package:garfin/main.dart';

/// The licence of a dependency Flutter cannot discover on its own.
///
/// FreeDroidWarn is an Android library resolved by Gradle. `LicenseRegistry` is
/// built from Dart package licences and the engine's vendored `NOTICES`, so it
/// never learns about it: the APK would ship an Apache-2.0 component whose text
/// appears in neither the curated licence screen nor the full page behind it.
///
/// `registerPlatformLicences()` is what closes that, and it is the kind of call
/// that can be deleted without anything going red — the page keeps rendering,
/// one licence shorter. This is the test that goes red instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test('the licence text ships as an asset', () {
    // `main.dart` loads this through `rootBundle`; pubspec.yaml must declare it
    // or that read throws at runtime and the entry silently never appears.
    expect(File('assets/licences/Apache-2.0.txt').existsSync(), isTrue);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/licences/'),
      reason: 'the licence text must be a declared asset to be loadable',
    );
  });

  test('platformDependencies is not empty', () {
    // Guards the two tests below, which would both pass vacuously against an
    // empty list — the exact shape of a check that cannot fail.
    expect(platformDependencies, isNotEmpty);
  });

  testWidgets('every platform dependency gets a licence entry', (tester) async {
    registerPlatformLicences();

    // `runAsync`, because draining the registry does real asset I/O — our own
    // entry loads the Apache text, and Flutter's default provider reads the
    // bundle's LICENSE. `testWidgets` fakes async by default, so the load
    // never completes and the stream never closes: the test does not fail, it
    // hangs until the ten-minute timeout. Measured.
    final packages = await tester.runAsync(() async {
      final seen = <String>{};
      await for (final entry in LicenseRegistry.licenses) {
        seen.addAll(entry.packages);
      }
      return seen;
    });

    expect(packages, isNotNull, reason: 'the registry stream never completed');
    for (final package in platformDependencies) {
      expect(
        packages!,
        contains(package),
        reason: '$package is linked into the APK with no licence entry',
      );
    }
  });

  testWidgets('the registered entry carries the Apache-2.0 text', (
    tester,
  ) async {
    // Not just *an* entry: an entry with the licence in it. An empty or
    // wrong-bodied entry produces a row that opens on nothing, which is the
    // failure this whole mechanism exists to prevent and looks identical from
    // the outside.
    registerPlatformLicences();

    // Same `runAsync` reason as above.
    final text = await tester.runAsync(() async {
      await for (final entry in LicenseRegistry.licenses) {
        if (!entry.packages.contains(platformDependencies.first)) continue;
        return entry.paragraphs.map((p) => p.text).join(' ');
      }
      return null;
    });

    expect(text, isNotNull, reason: 'no entry for the platform dependency');
    expect(text, contains('Apache License'));
    expect(text, contains('Version 2.0, January 2004'));
    // The grant itself, not only the title block — a truncated file would
    // still carry the heading.
    expect(text, contains('APPENDIX: How to apply the Apache License'));
  });
}
