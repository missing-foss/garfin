<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Garfin branding

The Garfin name and fish mark identify this project.

The artwork in `brand/svg/` is licensed **CC BY-SA 4.0**. Use it freely to write about, link to,
package, or review Garfin.

If you fork Garfin and distribute a modified version, please give it another name and another
mark, so nobody downloads yours thinking it is this one. The source code is GPL-3.0-or-later
and your fork is welcome — this request is about not confusing users, not about restricting code.

Garfin is not affiliated with, endorsed by, or connected to the Jellyfin project.
Jellyfin is a trademark of Jellyfin, Inc.

## Assets

| File | Use |
|---|---|
| `brand/svg/garfin-mark.svg` | The mark, full colour |
| `brand/svg/garfin-mark-mono.svg` | Single colour, `currentColor` — themed icons, notifications, print |
| `brand/svg/garfin-wordmark.svg` | Wordmark, eye-dot construction |
| `brand/svg/garfin-wordmark-mono.svg` | Wordmark, one colour |
| `brand/svg/garfin-lockup-h.svg` | Mark + word, horizontal — app bar, README, docs |
| `brand/svg/garfin-lockup-v.svg` | Stacked with tagline — splash, store listing |
| `brand/svg/garfin-icon-foreground.svg` | Android adaptive foreground, 108dp |
| `brand/svg/garfin-icon-background.svg` | Android adaptive background, flat `#2B2035` |

Run `brand/outline.sh` (run it from inside `brand/`) before shipping: the wordmark files contain live text and need Fredoka
installed to render correctly. Outlined copies land in `brand/svg/outlined/`.

**The Android launcher icons are generated, not drawn.** `brand/make-android-icons.sh`
renders `garfin-icon-foreground.svg` and `garfin-icon-background.svg` into
`android/app/src/main/res/mipmap-*/` — the adaptive foreground at 108dp per
density, and the legacy square icon composited from both. Re-run it after any
change to those two files rather than editing the PNGs, which are output.

It needs only `rsvg-convert`, and deliberately **not** `outline.sh`: the icon
carries the mark alone, with no live text, so it does not depend on Fredoka
being installed. Anything that rasterises the wordmark still does.

## Rules

- The mark sits left of, or above, the word. Never right.
- Clear space on all sides = half the mark's height.
- Minimum sizes: mark 20px · horizontal lockup 96px · stacked with tagline 120px.
- Don't recolour the mark outside the brand palette, stretch it, add effects, or
  place it on a busy photo.
- Don't combine it with the Jellyfin logo in a way that suggests an official relationship.

## Colours

| Token | Hex |
|---|---|
| Seed | `#7C5CD6` |
| Pearl | `#EADDFF` |
| Lilac | `#B69DF8` |
| Grape | `#8C6ED4` |
| Squid | `#241C36` |
| Deep | `#2B2035` |
| Foam | `#F6F2FA` |

Grape on Deep is 3.1:1 — never use it for text.

## Type

- **Fredoka** SemiBold — headings, titles, numbers, buttons, the wordmark
- **Nunito** — body and UI text
- **Roboto Mono** — tag strings and code

All three are SIL OFL 1.1 — Roboto Mono was relicensed from Apache 2.0 upstream, so the whole
bundled stack is already OFL and no swap to JetBrains Mono is needed. That means the fonts
impose no licence constraint of their own; it says nothing about which licences are available
to the project, which `CLAUDE.md` § Licence covers. The files live in `assets/fonts/`
alongside their licences (`OFL-Fredoka.txt`, `OFL-Nunito.txt`, `OFL-RobotoMono.txt`); register
them in `LicenseRegistry` so they appear under Settings → About → licences.

All three are variable fonts. The `wght` axis is driven by `TextStyle.fontWeight`; Fredoka also
carries a `wdth` axis, left at its default instance.
