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
licensed. It is **not** compatible with GPLv2 — see the note at the end of this
file.

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
font stack is OFL**. That matters for the relicensing note below.

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

## Note on a future relicence

`CLAUDE.md` states the project keeps a future relicence open, and Roboto was
avoided for the UI face for that reason. Two things follow:

- The **font stack imposes no constraint** — all three families are OFL-1.1,
  which is compatible with both GPLv2 and GPLv3.
- The **Dart packages do**. `dynamic_color` and `material_symbols_icons` are
  Apache-2.0, which is GPLv3-compatible but **not GPLv2-compatible**. If the
  relicence being kept open includes GPLv2, those two would have to be replaced
  first, and the dependency rule in `CLAUDE.md` would need to read
  *GPLv2-and-GPLv3-compatible* rather than *GPLv3-compatible*.

This is unresolved — see issue #1. Recorded here so the constraint is visible
at the point where dependencies are reviewed.
