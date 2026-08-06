// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:ui' as ui;

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
  // For `instantiateImageCodec` in the pixel assertions below.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  /// The data-extraction rules with `<!-- … -->` removed.
  ///
  /// Same reason again, and sharper here than anywhere else in this file: that
  /// file's comment quotes the Android documentation at length and therefore
  /// contains the literal strings `<device-transfer>`, `exclude`, `root` and
  /// `device_root` in prose. Unstripped, every assertion below would pass on a
  /// file whose rules had been deleted entirely.
  final extractionRules =
      File('android/app/src/main/res/xml/data_extraction_rules.xml')
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

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
    //
    // Tolerant about the argument, strict about the call. An earlier version
    // pinned the exact single-argument form, which would have gone red on two
    // *correct* edits: combining flags as `addFlags(FLAG_SECURE or …)`, which
    // is idiomatic, and `addFlags(FLAG_SECURE)` after a static import. Both
    // measured, along with the two that must stay caught — clearFlags beside
    // an addFlags of something else, and the call deleted.
    expect(activity, matches(RegExp(r'addFlags\([^)]*\bFLAG_SECURE\b')));
  });

  test('backup and device-to-device transfer are both off', () {
    // Issue #35. Nothing Garfin stores syncs to a cloud account — the standing
    // principle, not just this attribute. See docs/DECISIONS.md.
    //
    // `allowBackup="false"` alone is not enough and is the trap this guards.
    // Per Android's documentation, for apps targeting API 31+ it disables
    // cloud backup on some manufacturers' devices "but doesn't disable
    // device-to-device transfers for the app" — so a build checked on one
    // handset can be wrong on another. Both attributes, or neither works.
    expect(effective, contains('android:allowBackup="false"'));
    expect(
      effective,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );

    // And the rules file has to actually exclude things. An EMPTY section is
    // not "off", it is fully ON: "If there are no rules for a particular
    // backup mode, such as if the <device-transfer> section is missing, that
    // mode is fully enabled for all content except for no-backup and cache
    // directories." So `<device-transfer />` reads like a disable and is the
    // opposite of one, which is exactly the mistake worth a gate.
    //
    // Asserted per section rather than over the whole file, because the two
    // sections are what differ: excluding everything from <cloud-backup> while
    // leaving <device-transfer> empty is the plausible half-fix, and a
    // whole-file `contains` would pass it.
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp(
        '<$section>(.*?)</$section>',
        dotAll: true,
      ).firstMatch(extractionRules)?.group(1);

      expect(
        body,
        isNotNull,
        reason: '<$section> is missing, which enables that mode entirely',
      );
      // `path` is required on every rule; one without it is invalid rather
      // than broader. `root` covers credential-protected storage, where
      // shared_preferences lives; `device_root` is a separate location that
      // `root` does not reach.
      expect(
        body,
        contains('<exclude domain="root" path="." />'),
        reason: '<$section> does not exclude the app\'s private directory',
      );
      expect(
        body,
        contains('<exclude domain="device_root" path="." />'),
        reason: '<$section> does not exclude device-protected storage',
      );
    }
  });

  group('the launcher, which is the first thing anyone sees (#67)', () {
    // The icon shipped as Flutter's stock blue "F" through every release build
    // this project made, and nothing failed — an icon cannot fail, it can only
    // be wrong. The manifest and the resource tree are the only places that
    // is checkable without eyes on a device.

    test('the app is called Garfin, not garfin', () {
      // The launcher is where this name is read most often, and it was
      // lowercase from the `flutter create` template onward.
      expect(effective, contains('android:label="Garfin"'));
      expect(effective, isNot(contains('android:label="garfin"')));
    });

    test('there is an adaptive icon, and the manifest points at it', () {
      // minSdk is 26 and adaptive icons are universal from 26, so this is what
      // every device actually renders. Its absence is what left the stock icon
      // in place.
      final adaptive = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      );
      expect(adaptive.existsSync(), isTrue,
          reason: 'no adaptive icon means the legacy PNG is all there is');

      final xml = adaptive.readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      // Per element, not `contains`: the file names the foreground drawable
      // twice — once as `<foreground>` and once as `<monochrome>` — so a bare
      // substring check passes even when the foreground has been repointed at
      // something else. Mutation-tested; that is exactly what slipped through.
      expect(
        RegExp(r'<foreground[^>]*android:drawable="@mipmap/ic_launcher_foreground"')
            .hasMatch(xml),
        isTrue,
        reason: 'the foreground must be the brand mark',
      );
      expect(
        RegExp(r'<background[^>]*android:drawable="@color/ic_launcher_background"')
            .hasMatch(xml),
        isTrue,
      );

      expect(effective, contains('android:icon="@mipmap/ic_launcher"'));
      expect(effective, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
      // Round has the anydpi-v26 XML and deliberately *no* legacy PNG: at
      // minSdk 26 every device resolves the XML, so a round bitmap would be
      // five files nothing reads. Written down because its absence looks like
      // an oversight to anyone auditing the mipmap folders.
      expect(
        File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml')
            .existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png')
            .existsSync(),
        isFalse,
        reason: 'a legacy round PNG is unreachable at minSdk 26 — if one is '
            'wanted, the XML and the manifest are what decide, not this file',
      );
    });

    test('every density carries both icons', () {
      // A missing density does not fail a build; it makes one launcher, on one
      // phone, fall back to a scaled-up smaller asset.
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        for (final name in ['ic_launcher.png', 'ic_launcher_foreground.png']) {
          final file =
              File('android/app/src/main/res/mipmap-$density/$name');
          expect(file.existsSync(), isTrue, reason: 'missing $density/$name');
          expect(file.lengthSync(), greaterThan(0));
        }
      }
    });

    test('the launcher icon is the mark, not whatever was there before',
        () async {
      // **The one assertion that would have caught #67.** Every other check in
      // this group locks the *wiring* — the manifest points at the adaptive
      // XML, the XML points at the right drawables, the files exist and are
      // non-empty. All of that was true for every build this project ever made,
      // while the icon was Flutter's blue "F". Present, non-empty, correctly
      // referenced and completely wrong.
      //
      // So this reads pixels. Dominant colour rather than a checksum,
      // deliberately: a hash is the stronger check and the more brittle one —
      // it fails on a librsvg upgrade that changes one edge pixel, which is not
      // a defect. A flat brand field is 3/4 of this image and no stock asset
      // has it. Measured on the committed PNGs: #2B2035 is 76.6% at mdpi and
      // 78.6% at xxxhdpi; the stock icon's dominant colour is #000000.
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final histogram = await _colours(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        );
        final total = histogram.values.reduce((a, b) => a + b);
        final dominant = histogram.entries
            .reduce((a, b) => a.value >= b.value ? a : b);

        expect(dominant.key, _brandDeep,
            reason: '$density/ic_launcher.png is not on the brand field — '
                'found ${_hex(dominant.key)}');
        expect(dominant.value / total, greaterThan(0.5),
            reason: 'the brand field should dominate $density');

        // And the mark is actually on it. The field alone would pass on a
        // plain #2B2035 square, which is a wrong icon that happens to be the
        // right colour.
        expect(histogram[_brandLilac] ?? 0, greaterThan(0),
            reason: 'no brand lilac in $density/ic_launcher.png — '
                'the field is there but the fish is not');
      }
    });

    test('the adaptive foreground is a mark with padding, not a full square',
        () async {
      // The failure this catches is the plausible fix for the one above:
      // dropping the legacy icon into the foreground slot. It is the right
      // picture and the wrong asset — an opaque square on top of the adaptive
      // background, which every launcher then crops to its own shape, so the
      // mark shrinks and the brand field gains a visible edge inside the mask.
      //
      // Measured on the committed PNGs: 88.8% fully transparent at mdpi, 89.5%
      // at xxxhdpi. That padding *is* the safe zone.
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final histogram = await _colours(
          'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
        );
        final total = histogram.values.reduce((a, b) => a + b);
        final transparent = histogram.entries
            .where((e) => e.key & 0xFF == 0)
            .fold<int>(0, (sum, e) => sum + e.value);

        expect(transparent / total, greaterThan(0.5),
            reason: '$density/ic_launcher_foreground.png is mostly opaque — '
                'a foreground must be a mark with room around it');
        expect(histogram[_brandLilac] ?? 0, greaterThan(0),
            reason: 'no brand lilac in $density/ic_launcher_foreground.png');
      }
    });

    test('the icon background is the brand colour, in one place', () {
      // BRANDING.md's flat #2B2035, which garfin-icon-background.svg also
      // paints. A colour resource rather than a drawable, so a launcher's
      // parallax cannot scale or blur it.
      final colors =
          File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      expect(colors, contains('ic_launcher_background'));
      expect(colors.toUpperCase(), contains('#2B2035'));
    });

    test('the icons are generated, and the generator is in the repo', () {
      // The PNGs are output, not source. Without the script beside them the
      // next change to the mark would be a hand-edit of five bitmaps.
      final script = File('brand/make-android-icons.sh');
      expect(script.existsSync(), isTrue);
      final text = script.readAsStringSync();
      expect(text, contains('garfin-icon-foreground.svg'));
      expect(text, contains('garfin-icon-background.svg'));
    });
  });
}

/// `0xRRGGBBAA`, so a colour is one comparable int.
const _brandDeep = 0x2B2035FF;
const _brandLilac = 0xB69DF8FF;

String _hex(int colour) =>
    '#${(colour >> 8).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// Every distinct pixel of a PNG, counted.
///
/// Decoded through `dart:ui` rather than a package: `flutter_test` already has
/// a working codec, and the alternative is a new dependency for two assertions.
Future<Map<int, int>> _colours(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final counts = <int, int>{};
  for (var i = 0; i < data!.lengthInBytes; i += 4) {
    final colour = (data.getUint8(i) << 24) |
        (data.getUint8(i + 1) << 16) |
        (data.getUint8(i + 2) << 8) |
        data.getUint8(i + 3);
    counts[colour] = (counts[colour] ?? 0) + 1;
  }
  return counts;
}
