// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android settings that only fail on a real device, and only silently.
///
/// None is reachable from a widget test: the tests swap dio's transport for a
/// fake, so nothing touches Android's network stack, and there is no Activity
/// for `local_auth` to attach to. Several of these shipped broken or nearly so
/// once, which is why they are asserted from the manifest and the Activity
/// source rather than trusted to review.
///
/// Everything here reads *comment-stripped* text. These files explain silent
/// failures at length, so their prose names the very things being asserted.
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

  /// `MainActivity.kt` with its comments removed, for the same reason.
  ///
  /// Both assertions on that file are about what the *code* does, and its
  /// comments deliberately name the things being asserted — the class it must
  /// extend, the flag it must set — at length, because each explains a failure
  /// that is silent. So an unstripped `contains` can pass on the prose while
  /// the code beside it is wrong. That is not hypothetical: it is exactly how
  /// the FragmentActivity assertion below came to be half-vacuous (#37).
  ///
  /// Block comments go too. Kotlin has both, and `//` alone would leave a
  /// `/* … */` one able to satisfy a match.
  ///
  /// **One alternation, not two passes.** Running the two strips in sequence is
  /// wrong in either order, because each order lets the *other* comment form
  /// open a match that swallows real code — a false positive on correct
  /// source, not a hole, but one an ordinary edit would trip:
  ///
  /// - block-then-line: `// see the /* pattern` starts a block match that eats
  ///   everything up to the next `*/`, which the first KDoc supplies.
  /// - line-then-block: `/* see http://example.com */` loses its terminator to
  ///   the line strip, and the block match then runs on to a later `*/`.
  ///
  /// Both measured. A single left-to-right alternation has neither problem:
  /// whichever form opens first consumes its own contents, so a `/*` inside a
  /// line comment and a `//` inside a block comment are both inert.
  final activity =
      File('android/app/src/main/kotlin/com/mfoss/garfin/MainActivity.kt')
          .readAsStringSync()
          .replaceAll(RegExp(r'//[^\n]*|/\*.*?\*/', dotAll: true), '');

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
    expect(effective, contains('android.permission.INTERNET'));
  });

  test('local network access is declared', () {
    // Android 16+ Local Network Protection: a private-range address needs this
    // on top of INTERNET, and without it the connection fails with no prompt.
    // Garfin exists to talk to a server on the user's own network, so this is
    // the one permission it cannot do without.
    expect(effective, contains('android.permission.LOCAL_NETWORK_ACCESS'));
  });

  test('MainActivity is a FragmentActivity, as local_auth requires', () {
    // `local_auth` shows an androidx BiometricPrompt, which is a Fragment.
    // Getting this wrong does not crash: the plugin answers
    // NOT_FRAGMENT_ACTIVITY, which surfaces as an unlock error, so the gate
    // stands there and can never be opened. Ground rule 9.
    //
    // Assert the *declaration*, not a bare substring (#37). This previously
    // read the unstripped source for `contains('FlutterFragmentActivity')`,
    // which the class comment above satisfies on its own, leaving the negative
    // assertion to carry the test alone — and that one only recognises the
    // fully-qualified import. Measured: extending FlutterActivity was caught
    // when imported as `io.flutter.embedding.android.FlutterActivity`, and
    // missed entirely when imported as `io.flutter.embedding.android.*`.
    // Matching the declaration closes that without depending on import style.
    expect(
      activity,
      matches(RegExp(r'class\s+MainActivity\s*:\s*FlutterFragmentActivity\b')),
    );

    // Kept as a second line of defence: it catches a fully-qualified import of
    // the wrong class even if the declaration were somehow satisfied.
    expect(
      activity,
      isNot(contains('io.flutter.embedding.android.FlutterActivity')),
    );
  });

  test('MainActivity sets FLAG_SECURE', () {
    // Issue #26. Without it Android writes the window to
    // /data/system_ce/0/snapshots/<taskId>.jpg on the way out, and that file
    // outlives the idle timeout — so the switcher shows unlocked content back
    // while resume demands auth. Ground rule 9.
    //
    // Reads the comment-stripped source, for the reason given where it is
    // built: the comment above the flag names it repeatedly, so a bare
    // `contains` would pass on the prose alone with the call deleted.
    //
    // Assert the *call*, not two substrings. `contains('FLAG_SECURE')` and
    // `contains('addFlags')` never have to refer to the same statement, so
    // `clearFlags(…FLAG_SECURE)` beside `addFlags(…FLAG_KEEP_SCREEN_ON)` —
    // the exact inverse of what this guards — satisfied both and reported
    // green. Measured; it is the same defect as #37, one assertion down.
    //
    // **What this cannot reach: whether the call runs.** Wrapping it in
    // `if (false)`, or moving it to a method nobody calls, both leave this
    // green, and no assertion over source text can tell the difference. The
    // gate proves the call is *written*, not that it *executes*. The runtime
    // half is the device measurement in SECURITY.md — background the app and
    // pull /data/system_ce/0/snapshots/<taskId>.jpg — and a green test here
    // must not be read as standing in for it.
    expect(
      activity,
      matches(
        RegExp(r'addFlags\(\s*WindowManager\.LayoutParams\.FLAG_SECURE\s*\)'),
      ),
    );
  });
}
