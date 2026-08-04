// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two Android settings that only fail on a real device, and only silently.
///
/// Neither is reachable from a widget test: the tests swap dio's transport for
/// a fake, so nothing touches Android's network stack, and there is no Activity
/// for `local_auth` to attach to. Both of these shipped broken or nearly so
/// once, which is why they are asserted from the manifest itself rather than
/// trusted to review.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  /// The manifest with `<!-- … -->` removed.
  ///
  /// Needed for the negative assertions: the comments here deliberately *name*
  /// the attributes that must not be set, to warn the next person off them, and
  /// a bare `isNot(contains(…))` matches the warning as readily as the mistake.
  final effective = manifest.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );

  test('no cleartext exemption is granted', () {
    // Measured on GrapheneOS / Android 17 with a control build: plain HTTP to a
    // LAN Jellyfin works without either of these. Android's policy is enforced
    // by the Java HTTP stacks and dio uses `dart:io` sockets, which never
    // consult it. Both were tried during a diagnosis and proved inert, so this
    // guards against them coming back as a plausible-looking fix — they permit
    // unencrypted traffic app-wide and buy nothing. See SECURITY.md.
    expect(effective, isNot(contains('usesCleartextTraffic')));
    expect(effective, isNot(contains('networkSecurityConfig')));
  });

  test('INTERNET is declared in the MAIN manifest, not just debug', () {
    // This shipped broken. Flutter's scaffold puts INTERNET in the debug and
    // profile manifests for hot reload, so every debug build has network
    // access and every release build has none — and `dev/verify.sh` and CI
    // both build *debug*, so nothing here could catch it. It took a real
    // device and three wrong diagnoses.
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('local network access is declared', () {
    // Android 16+ Local Network Protection: a private-range address needs this
    // on top of INTERNET, and without it the connection fails with no prompt.
    // Garfin exists to talk to a server on the user's own network, so this is
    // the one permission it cannot do without.
    expect(
      manifest,
      contains('android.permission.LOCAL_NETWORK_ACCESS'),
    );
  });

  test('MainActivity is a FragmentActivity, as local_auth requires', () {
    // `local_auth` shows an androidx BiometricPrompt, which is a Fragment.
    // Getting this wrong does not crash: the plugin answers
    // NOT_FRAGMENT_ACTIVITY, which surfaces as an unlock error, so the gate
    // stands there and can never be opened. Ground rule 9.
    final activity = File(
      'android/app/src/main/kotlin/com/mfoss/garfin/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('FlutterFragmentActivity'));
    expect(
      activity,
      isNot(contains('io.flutter.embedding.android.FlutterActivity')),
    );
  });
}
