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

GPL-3.0-or-later. **Every dependency must be GPLv3-compatible.** Do not add anything
GPLv3-incompatible or proprietary without asking.

**GPLv2 compatibility is deliberately not maintained.** Apache-2.0 is GPLv3-compatible but not
GPLv2-compatible, and the app already ships Apache-2.0 material: `dynamic_color` is compiled in,
and its Apache-2.0 grant is verifiable in the app's own `assets/flutter_assets/NOTICES.Z`. That
door is closed, and it was closed by a deliberate dependency choice, not by accident. Independently, a downward relicence would need every contributor's consent, which
`CONTRIBUTING.md` does not collect — it takes contributions under GPL-3.0-or-later and grants
no relicensing right. So don't reject a dependency for being GPLv2-incompatible; reject it for
being GPLv3-incompatible.

Checked and fine, as of 2026-08-03:

Read from each package's own shipped `LICENSE` file, not from its pub.dev page —
the pub.dev metadata is not always right. Full detail in `THIRD_PARTY_NOTICES.md`.

| Dependency | Licence |
|---|---|
| Flutter/Material | BSD-3-Clause |
| dio, flutter_riverpod, cached_network_image, mocktail | MIT |
| shared_preferences, flutter_secure_storage, logging, intl, flutter_lints | BSD-3-Clause |
| **local_auth** (with `_android`, `_platform_interface`, and the unshipped `_darwin` / `_windows`) | BSD-3-Clause |
| dynamic_color | Apache-2.0 |
| Fredoka, Nunito, **Roboto Mono** | SIL OFL 1.1 |

Roboto Mono was relicensed from Apache 2.0 to OFL 1.1 upstream, so the **entire bundled font
stack is now OFL** — the JetBrains Mono swap that BRANDING.md used to suggest is no longer
needed. That means the fonts impose no licence constraint of their own; it does not mean a
GPLv2 relicence is available, which the paragraph above explains it is not.

## Ground rules

1. **Never write to Jellyfin without a preview.** Every tag change shows the exact
   additions and removals before it is applied. No write on toggle. The preview also carries
   the child's **current** server-computed count, and hard-warns when the removal would strip
   the child's tag from the **last item still carrying it** — their `AllowedTags` would then
   match nothing and they would see *nothing*, not everything, and a bare `− tag` line does not
   convey that. Note this is a **count of tagged items**, not a policy field and not a
   visibility computation: rule 8 means Garfin cannot alter `AllowedTags` itself, so the
   policy entry survives and simply stops matching. Rule 4 is untouched — no rating cap is
   involved. After applying, re-fetch and report the **verified** new count; that is what
   explains a share the rating cap swallowed.
2. **`POST /Items/{id}` replaces the whole item.** Always `GET` the full metadata object first,
   mutate only `Tags`, and post the complete object back. Dropping fields corrupts the library.
   "The full object" is not one thing — the DTO varies by endpoint and by `Fields`. The exact
   endpoint and field list are **derived empirically, not assumed**; see `docs/JELLYFIN-API.md`.
   Every PR touching the write path must show a before/after round-trip diff against a real
   server.
3. **Allow-list and block-list are opposite verbs.** Detect the mode per user and invert every
   action. Never mix `AllowedTags` and `BlockedTags` on one account.
4. **Never compute visibility client-side.** Fetch counts twice — once as the admin, once as
   the child — and let the server apply the policy. The rating cap silently overrides tags, and
   guessing gets it wrong. This is why rule 1 previews the *current* count rather than a
   predicted one: a predicted count would mean simulating the server's policy evaluation here,
   which is exactly what this rule forbids.
5. **Collection writes pre-flight, then fix forward. They do not roll back.** `GET` every
   member before writing anything and abort if any read fails — reads are free and catch most
   failures before a single write. The pre-flight keeps **no bodies**: every write starts with its
   own fresh `GET`, and what it checks is not "the read succeeded" but "the item that came back is
   the item asked for" (`docs/JELLYFIN-API.md`: the all-zero GUID answers 200 with the root
   folder). A collection write covers the **container as well as every member** — measured, members
   alone leave the set unreachable and the container alone leaves it empty — with the container
   written **last** on an addition and **first** on a removal, so its label only ever means "the
   whole set is here". If a write still fails mid-batch, retry *that item*; never
   undo the ones that succeeded. Tag writes are idempotent, so retrying is safe and repeatable
   while undoing is neither, and every undo is another full-object replace under rule 2 on an
   item that was fine. Surface the exact state — "7 of 12 tagged" — and let the user choose to
   finish or remove all. Both choices are idempotent and user-initiated.

   **The user-facing Undo is a new forward write, never a restore**, and is not an exception to
   this rule — it is the same thing. Fresh `GET`, remove the specific tag Garfin added, post the
   full object back. It reverses the *effect*, not the object. **Garfin never re-posts a
   previously captured item body.** A button labelled Undo alongside a rule saying "never undo"
   looks contradictory until you see that both are idempotent forward writes; that is exactly
   what makes them safe. What this rule forbids is *silent, automatic* rollback of a batch, not
   an explicit user-initiated reversal.
6. **Ask before destructive or cascading changes.** Adding a film in a collection prompts once.
   Removing never cascades.
7. Admin account required. Refuse non-admin logins with a clear message rather than failing later.
8. **Garfin is read-only on user policy.** Never `POST /Users/{id}/Policy`. It is a full-object
   replace over the child's entire permission set — `EnabledFolders`, `IsAdministrator`, and
   `MaxParentalRating`, which is the actual safety control. A dropped field there does not
   corrupt metadata, it silently removes a child's restrictions. Read policy; write only items.
   **A read-modify-write of only `AllowedTags` is not an exception** — it is the same endpoint and
   the same full replace, and looking safer is the problem with it. The consequence, deliberate:
   Garfin cannot give a child their *first* label, so that one-time setup happens in Jellyfin. See
   `docs/DECISIONS.md` and the Kids screen in `docs/UI-SPEC.md`.
9. **The app itself is gated behind device auth.** Garfin holds an admin token on a phone that
   gets handed to children by design — that is the product's normal interaction, and it is
   precisely the case device lock does not cover. Biometric/PIN on cold start and on resume
   after an idle timeout, which is a Settings option.

## Conventions

- `lib/models/`, `lib/repositories/`, `lib/providers/`, `lib/screens/`, `lib/widgets/`
- Prefer composition over deep widget trees; extract anything over ~80 lines.
- No `print` — use a logger, and never log tokens, passwords, or Quick Connect secrets.
- Copy style: plain and warm, never cute about permissions. See `docs/DECISIONS.md` § Voice.
- Write tests for the tag-diff logic and the allow/block inversion. Those are where bugs hide.
- **Run the grep your sentence implies.** Prose in `SECURITY.md`, `THIRD_PARTY_NOTICES.md` and
  doc comments makes checkable claims — "written at seven call sites", "the only URL literals",
  "does not survive an uninstall" — and every one of those has been wrong at least once while
  the code beside it was correct. A claim scoped to what you searched rather than to what exists
  reads exactly like a verified one. Tests here get mutation-tested as a matter of course; give
  sentences the same treatment, which costs one command.
- **A gate you have not tried to break is not a gate.** Mutation-test anything you add or rewrite
  that is supposed to catch something — delete the thing it guards and watch it fail. Two gates
  in this repo were vacuous when written.

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

Sign-in works, behind the device unlock gate. `lib/main.dart` resolves `SharedPreferences` and the
device identity, then hands off to `UnlockGate` wrapping `lib/screens/app_root.dart`, which shows
the sign-in screen or the (placeholder) home depending on whether a session restores.
`lib/repositories/` holds the Jellyfin client, the auth repository, the Quick Connect pairing and
the device-unlock wrapper; `lib/providers/` wires them into Riverpod. Tracked in the build-order
epic; phases get their own issue when they are next.

The write path is `lib/repositories/assign_repository.dart` — one item through `apply`, a whole
collection through `applyToCollection`, and neither accepts an item object. `dev/live_collection_roundtrip.dart`
runs the collection write against a real server and prints the before/after diff, which is the
standing gate in `docs/JELLYFIN-API.md`; it sits in `dev/` rather than `test/` so it can never
become a skipped check that still reports green.

- [x] **Round-trip experiment** — done. The write path's read strategy is measured, not assumed:
      `GET /Users/{uid}/Items/{id}`, no `Fields` needed. See `docs/JELLYFIN-API.md`
1. [x] Jellyfin client + auth (Quick Connect and password), admin check
2. [x] Device unlock gate (`local_auth`) — rule 9. Early, because every later screen sits behind it
3. [x] User list with policy parsing → Kids screen
4. [x] Library grid with the child selector — filter bar and infinite scroll still open in #44
5. [x] Assign sheet with tag diff, counts, and the write path
6. [x] Collections, pre-flight and fix-forward
7. Settings
8. Activity log

`local_auth` landed with step 2. Its licence was read from the package's own shipped `LICENSE`
file rather than from pub.dev, per the § Licence note above: **BSD-3-Clause**, Copyright 2013 The
Flutter Authors, identical text across `local_auth`, `local_auth_android` and
`local_auth_platform_interface`.

`MainActivity` extends `FlutterFragmentActivity`, not `FlutterActivity` — `local_auth` shows an
androidx `BiometricPrompt`, which is a Fragment. Getting that wrong does not crash: the plugin
answers `NOT_FRAGMENT_ACTIVITY` and the gate silently never appears.
