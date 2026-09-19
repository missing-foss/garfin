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

  /// The About screen groups the 201-package licence list into *what Garfin
  /// chose* and *what Flutter brought*, and the first half is this const.
  ///
  /// A hand-kept list of dependencies is exactly the kind that rots: add a
  /// package, forget the list, and the screen quietly under-reports what the
  /// app depends on. Deriving it from `pubspec.yaml` here is what stops that,
  /// the same trick [appVersion] uses.
  ///
  /// **SDK packages are excluded on both sides**, because they ship under
  /// Flutter's own licence entry rather than one of their own — a row for
  /// `flutter_localizations` would open on nothing.
  test('directDependencies matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final block = RegExp(r'^dependencies:$(.*?)^dev_dependencies:$',
            multiLine: true, dotAll: true)
        .firstMatch(pubspec);
    expect(block, isNotNull, reason: 'no `dependencies:` block in pubspec.yaml');

    final lines = block!.group(1)!.split('\n');
    final found = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final name = RegExp(r'^  ([a-z0-9_]+):').firstMatch(lines[i]);
      if (name == null) continue;
      // `foo:\n    sdk: flutter` — the SDK form, which carries no licence of
      // its own. Looked at rather than assumed: the value may be on the same
      // line (`intl: any`) or the next.
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      if (next.trimLeft().startsWith('sdk:')) continue;
      if (name.group(1) == 'flutter') continue;
      found.add(name.group(1)!);
    }
    found.sort();

    expect(found, isNotEmpty, reason: 'parsed no dependencies — the regex broke, '
        'and an empty list would pass a comparison against an empty const');
    expect(
      directDependencies,
      found,
      reason: 'update directDependencies in lib/app_info.dart when you add or '
          'remove a dependency',
    );
  });
}
