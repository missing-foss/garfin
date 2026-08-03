<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Third-Party Notices — Garfin

Garfin's own code is `GPL-3.0-or-later` (see [`LICENSE`](LICENSE)). The released
APK additionally redistributes the components below, each under its own licence.

Every licence here was read from the component's **own shipped `LICENSE` file**,
not from its pub.dev metadata, which is not always accurate. Machine-readable
attribution lives in [`REUSE.toml`](REUSE.toml) and the per-file SPDX headers.

Garfin is not affiliated with, endorsed by, or connected to the Jellyfin project.
Jellyfin is a trademark of Jellyfin, Inc. No Jellyfin mark is used in Garfin's
name, icon, or artwork.

## Flutter

The application embeds the Flutter engine (BSD-3-Clause, Copyright 2014 The
Flutter Authors) and its Dart package dependencies. The complete, auto-generated
licence collection for all of them ships inside every build and is viewable
programmatically through Flutter's `LicenseRegistry` — surfaced in-app under
Settings → About → licences.

The Android platform scaffolding under `android/` is also Flutter's
(BSD-3-Clause); see the `android/**` entry in `REUSE.toml`.

## Dart packages

Direct dependencies. Transitive dependencies are covered by the Flutter
`LicenseRegistry` collection above.

| Package | Licence | Copyright |
|---|---|---|
| `dio` | MIT | 2018 Wen Du (wendux) |
| `flutter_riverpod`, `riverpod` | MIT | 2020 Remi Rousselet |
| `cached_network_image` | MIT | Rene Floor |
| `shared_preferences` | BSD-3-Clause | 2013 The Flutter Authors |
| `flutter_secure_storage` | BSD-3-Clause | 2017 German Saprykin |
| `logging`, `intl` | BSD-3-Clause | 2013 the Dart project authors |
| `dynamic_color` | Apache-2.0 | Google LLC |
| `material_symbols_icons` | Apache-2.0 | Google LLC (icons), package author |

Development-only, not shipped in the APK: `mocktail` (MIT, 2026 Felix Angelov),
`flutter_lints` (BSD-3-Clause, 2013 The Flutter Authors).

Apache-2.0 is compatible with GPLv3 and is therefore fine for this project as
licensed. See the note at the end of this file on why GPLv2 is not a
consideration.

## Fonts — SIL Open Font License 1.1

Three families are bundled in `assets/fonts/*.ttf` so the wordmark and UI match
across surfaces. All three are SIL OFL 1.1:

- **Fredoka** — Copyright 2016 The Fredoka Project Authors
  (https://github.com/hafontia/Fredoka-One) — headings, titles, numbers,
  buttons, and the Garfin wordmark.
- **Nunito** — Copyright 2014 The Nunito Project Authors
  (https://github.com/googlefonts/nunito) — body and UI text.
- **Roboto Mono** — Copyright 2015 The Roboto Mono Project Authors
  (https://github.com/googlefonts/robotomono) — tag strings and code.

Roboto Mono was relicensed upstream from Apache-2.0 to OFL-1.1, so the **entire
bundled font stack is OFL** and the fonts impose no licence constraint of their
own.

The fonts ship **unmodified**, and no Reserved Font Name has been used for any
modified version. Each family's licence text ships in the APK alongside the
font it covers:

- `assets/fonts/OFL-Fredoka.txt`
- `assets/fonts/OFL-Nunito.txt`
- `assets/fonts/OFL-RobotoMono.txt`

The canonical text is also at [`LICENSES/OFL-1.1.txt`](LICENSES/OFL-1.1.txt).
It is not duplicated inline here because the app already redistributes all three
copies above; a reader of the APK has the licence in hand without this file.

Flutter's Material icons (Apache-2.0) are part of the Flutter distribution.

## Artwork

The Garfin mark, wordmark, and lockups (`brand/svg/`) are original work by
missing-foss, licensed **CC BY-SA 4.0** — deliberately *not* GPL. Copyleft on a
logo would let a fork ship a modified app under Garfin's mark. Forks are welcome
and should rename. See [`BRANDING.md`](BRANDING.md).

`brand/garfin-design-pack.html` is covered by the same terms. The mark is drawn
as inline vector paths, so it carries no third-party asset terms.

## Note on GPLv2

Earlier drafts of `CLAUDE.md` said the project kept a future GPLv2 relicence
open. **It does not, and it should not be treated as a live constraint.** This
is recorded here because it kept resurfacing in review.

Apache-2.0 is GPLv3-compatible but not GPLv2-compatible, and Apache-2.0 material
already ships in the APK:

- **`material_symbols_icons`** — its icon font is bundled, and its Apache-2.0
  grant is verifiable in the app's own `assets/flutter_assets/NOTICES.Z`.
- **`dynamic_color`** — Apache-2.0 Dart code, compiled in.

Both are deliberate dependencies, so the door was closed by choice rather than
oversight. Independently of the dependency tree, a downward relicence would
require **every contributor's consent**: `CONTRIBUTING.md` takes contributions
under GPL-3.0-or-later and collects no CLA or relicensing grant, so no such
consent exists to rely on.

The bundled fonts are all OFL-1.1 and impose no constraint of their own — but
that establishes only that the *fonts* are unconstraining, not that any
particular relicence is available.

For completeness, one thing that is often assumed and is wrong: the icons font
Flutter bundles via `uses-material-design: true`
(`assets/flutter_assets/fonts/MaterialIcons-Regular.otf`) is **CC BY 4.0**, per
Flutter's own `MaterialIcons_LICENSE.txt`, not Apache-2.0. The Apache-2.0
exposure comes from the two packages named above.

The operative rule is therefore simply: **every dependency must be
GPLv3-compatible.** Refs #1.
