// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// Identity Garfin presents to Jellyfin in the `Authorization` header, and what
/// the server shows in Dashboard → Devices.
library;

/// The `Client="…"` value. Fixed — this is the product name, not the device.
const appClientName = 'Garfin';

/// The `Version="…"` value.
///
/// Kept in sync with `pubspec.yaml`'s `version:` by `test/app_info_test.dart`,
/// which fails if the two drift. Reading it at runtime instead would mean a
/// `package_info_plus` dependency for one string, and every new dependency
/// costs a licence review (`CONTRIBUTING.md`).
const appVersion = '0.2.0';

/// The packages Garfin itself chose to depend on.
///
/// **Why a curated list exists at all.** The built-in licence page lists every
/// package compiled in — measured on the 0.2.0 release build, **201 of them**,
/// almost all of it the Flutter engine's own vendored C++: `icu` alone carries
/// 559 licence entries, then `harfbuzz`, `skia`, `angle`, `boringssl`. None of
/// that is a decision anyone made here, and it buries the dozen that were.
///
/// **This groups the display; it hides nothing.** The full page is still one
/// tap away, still generated from what is actually linked, and is still the
/// authoritative list — but "generated from what is actually linked" holds only
/// because `main.dart` registers [platformDependencies] by hand.
/// `LicenseRegistry` is built from Dart package licences and the engine's
/// vendored `NOTICES`, and neither sees a Gradle artifact. Measured on the
/// release APK: `FreeDroidWarn` is present in `classes.dex`, and `freedroidwarn`
/// and `woheller69` each match **zero** times in the 1,412,761 bytes `NOTICES.Z`
/// decompresses to. The controls are whole-line matches for five pub
/// dependencies — `dio`, `flutter_riverpod`, `shared_preferences`,
/// `url_launcher`, `local_auth` — which appear **once each**, so the search does
/// reach package names and the zero is the artifact's absence rather than a
/// grep that never worked. Remove that registration and this sentence goes
/// quietly false.
///
/// Match whole lines. A substring count is the wrong instrument here and gives
/// a figure that flatters the control: `grep -ci dio` returns twelve, but nine
/// of those are a `Cendio AB` copyright line in someone else's licence, one is
/// `dio_web_adapter` and one is `audiocodes`. One line is the entry.
///
/// Nothing here is a claim about *which* licence a package
/// carries — that would be inferring something legal from free text. It is only
/// a claim about which packages this app asked for, which is a fact `pubspec.yaml`
/// already holds.
///
/// **SDK packages are absent on purpose.** `flutter_localizations` is declared
/// `sdk: flutter` and ships under Flutter's own entry rather than its own, so
/// listing it here would produce a row with no licence behind it. Confirmed
/// against the release build's `NOTICES`: of twelve direct dependencies, that
/// is the one with no entry of its own.
///
/// Kept in sync with `pubspec.yaml` by `test/app_info_test.dart`, the same way
/// [appVersion] is, because a list that silently rots is worse than no list.
const directDependencies = <String>[
  'cached_network_image',
  'diacritic',
  'dio',
  'dynamic_color',
  'flutter_riverpod',
  'flutter_secure_storage',
  'intl',
  'local_auth',
  'logging',
  'shared_preferences',
  'url_launcher',
];

/// Dependencies that are linked into the APK but are not pub packages.
///
/// **Why this is a second list rather than more entries in
/// [directDependencies].** That one is derived from `pubspec.yaml` by
/// `test/app_info_test.dart` — a list that cannot silently rot, because the
/// test rebuilds it from the file that defines it. Adding a name `pubspec.yaml`
/// does not contain would mean loosening that test, and the test is the only
/// reason the list is trustworthy.
///
/// So these are kept apart: one list the build system can prove, one it cannot.
/// This one is hand-kept and has to be, which is worth knowing when reading it.
///
/// **Nothing here reaches `LicenseRegistry` on its own.** These arrive through
/// Gradle, and the registry is built from Dart package licences and the
/// engine's vendored `NOTICES`. `main.dart` registers their licence text
/// explicitly; without that the licence page would show a row that opens on
/// nothing. `test/platform_licence_test.dart` is what keeps the two in step.
const platformDependencies = <String>['FreeDroidWarn'];

/// Jellyfin's own documentation on user accounts and parental controls.
///
/// **Theirs, not a summary here.** The setting names and the screens belong to
/// Jellyfin and a restatement would go stale the first time they moved one —
/// and Garfin cannot perform the step it is pointing at, because giving a child
/// their first label is a policy write and ground rule 8 forbids it.
///
/// A constant rather than a localised string for the same reason as
/// [sourceUrl]: a URL is the same in every locale.
const jellyfinUsersDocsUrl =
    'https://jellyfin.org/docs/general/server/users/adding-managing-users';

/// Where the source lives, shown in Settings → About.
///
/// A constant rather than a localised string: a URL is the same in every
/// locale, and putting it in the catalogue would invite a translator to
/// "translate" it. It is here rather than inline in the screen because
/// `dev/verify.sh` fails any `Text` built from a string literal on sight — a
/// rule worth keeping blunt, since the failure it catches is English leaking
/// into every locale. (Writing that pattern out in this comment tripped the
/// grep, which is the rule proving itself.)
const sourceUrl = 'https://github.com/missing-foss/garfin';
