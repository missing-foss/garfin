// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/app_info.dart';

/// `appVersion` is a const because reading the real one at runtime would mean a
/// `package_info_plus` dependency for one string, and every new dependency
/// costs a licence review. This is what keeps the const honest.
///
/// Without it the version Jellyfin lists in Dashboard → Devices drifts from the
/// version the app actually is, silently, and stays wrong until someone
/// notices.
void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
            .firstMatch(pubspec);

    expect(match, isNotNull, reason: 'no `version:` line found in pubspec.yaml');
    expect(
      appVersion,
      match!.group(1),
      reason: 'bump lib/app_info.dart when you bump pubspec.yaml',
    );
  });
}
