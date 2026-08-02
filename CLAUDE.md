<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Garfin

An Android app for managing Jellyfin parental controls through tags. Pick a child, browse what
they can't see yet, hand them a film, a series, or a whole collection in one tap.

**Not affiliated with the Jellyfin project.** Jellyfin is a trademark of Jellyfin, Inc.

## Read first

- `docs/DECISIONS.md` — every design decision and why. Read before proposing an alternative;
  most obvious alternatives were already considered and rejected for a reason.
- `docs/UI-SPEC.md` — screen-by-screen behaviour.
- `docs/JELLYFIN-API.md` — endpoints, quirks, and the things that will bite.
- `docs/ui-mockup.jsx` — a clickable React mockup of the whole app. It is a **reference, not
  source**. Do not port it, do not import from it, do not treat its structure as the app's
  architecture. It exists to show layout, flow, and copy.
- `BRANDING.md` — logo, colours, type, and their licences.

## Stack

- **Flutter**, Material 3, dark-first, `ColorScheme.fromSeed(seedColor: Color(0xFF7C5CD6))`
  with `DynamicColorBuilder` for Material You on Android 12+.
- **Fonts**: Fredoka SemiBold (headings, titles, numbers, buttons), Nunito (body),
  Roboto Mono (tags and code). Declared in `pubspec.yaml`, files in `assets/fonts/`.
- **HTTP**: `dio` or `http` — no generated Jellyfin SDK, the surface we need is small.
- **State**: Riverpod. Keep the Jellyfin client in a repository layer; widgets never call HTTP.
- **Storage**: `shared_preferences` for settings. **Never** the access token — that goes in
  `flutter_secure_storage`.
- **Minimum SDK**: 26. Target the current stable.

## Licence

GPL-3.0-or-later. Every dependency you add must be compatible. **Do not add anything
Apache-2.0-incompatible or proprietary without asking.** Apache 2.0 is GPLv3-compatible but not
GPLv2-compatible; we deliberately avoided Roboto for the UI face to keep relicensing open.

Checked and fine, as of 2026-08-02:

Read from each package's own shipped `LICENSE` file, not from its pub.dev page —
the pub.dev metadata is not always right. Full detail in `THIRD_PARTY_NOTICES.md`.

| Dependency | Licence |
|---|---|
| Flutter/Material | BSD-3-Clause |
| dio, flutter_riverpod, cached_network_image, mocktail | MIT |
| shared_preferences, flutter_secure_storage, logging, intl, flutter_lints | BSD-3-Clause |
| dynamic_color, material_symbols_icons | Apache-2.0 |
| Fredoka, Nunito, **Roboto Mono** | SIL OFL 1.1 |

Roboto Mono was relicensed from Apache 2.0 to OFL 1.1 upstream, so the **entire font stack is
now OFL** — the JetBrains Mono swap that BRANDING.md used to suggest is no longer needed, and
nothing in the font stack blocks a future GPLv2 relicence.

## Ground rules

1. **Never write to Jellyfin without a preview.** Every tag change shows the exact
   additions and removals before it is applied. No write on toggle.
2. **`POST /Items/{id}` replaces the whole item.** Always `GET` the full metadata object first,
   mutate only `Tags`, and post the complete object back. Dropping fields corrupts the library.
3. **Allow-list and block-list are opposite verbs.** Detect the mode per user and invert every
   action. Never mix `AllowedTags` and `BlockedTags` on one account.
4. **Never compute visibility client-side.** Fetch counts twice — once as the admin, once as
   the child — and let the server apply the policy. The rating cap silently overrides tags, and
   guessing gets it wrong.
5. **Collection writes are batched and roll back together.** A half-tagged set is worse than
   no change.
6. **Ask before destructive or cascading changes.** Adding a film in a collection prompts once.
   Removing never cascades.
7. Admin account required. Refuse non-admin logins with a clear message rather than failing later.

## Conventions

- `lib/models/`, `lib/repositories/`, `lib/providers/`, `lib/screens/`, `lib/widgets/`
- Prefer composition over deep widget trees; extract anything over ~80 lines.
- No `print` — use a logger, and never log tokens, passwords, or Quick Connect secrets.
- Copy style: plain and warm, never cute about permissions. See `docs/DECISIONS.md` § Voice.
- Write tests for the tag-diff logic and the allow/block inversion. Those are where bugs hide.

## Definition of done for a feature

Builds, passes `flutter analyze` with no warnings, works offline-degraded (shows cached data
and a clear error rather than a blank screen), and has no hardcoded strings outside a
localisation file if l10n has been set up.

## Toolchain

Installed under `~/sdk/`, on `PATH` via `~/.bashrc`. Not part of the repo.

- Flutter 3.44.8 stable · Dart 3.12.2 · `~/sdk/flutter`
- Android SDK platform 36, build-tools 36.0.0, platform-tools · `~/sdk/android` (`ANDROID_HOME`)
- JDK 17 (system) · `minSdk 26`, `compileSdk`/`targetSdk` follow Flutter's default
- No emulator image is installed. `flutter devices` shows Linux desktop only; plug in a
  physical device over `adb`, or `sdkmanager "system-images;android-36;google_apis;x86_64"`.

Analytics are off (`flutter --disable-analytics`, `FLUTTER_SUPPRESS_ANALYTICS=true`).

    flutter analyze          # must be clean — it is part of the definition of done
    flutter test
    flutter build apk --debug

## Status

Scaffolded, no features yet. `lib/main.dart` boots the themed shell and shows a placeholder;
`lib/theme.dart` holds the seed colour and font wiring. The convention directories exist and
are empty. Build order:
1. Jellyfin client + auth (Quick Connect and password), admin check
2. User list with policy parsing → Kids screen
3. Library grid with the child selector
4. Assign sheet with tag diff + write path
5. Collections and cascade
6. Settings
7. Activity log
