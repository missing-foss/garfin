// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// The Phosphor icons the app draws, regular weight (#166).
///
/// **Phosphor, not Material**: ruled, after a side-by-side of Lucide, Tabler
/// and Phosphor. It ships as `assets/fonts/Phosphor.ttf` from
/// `@phosphor-icons/web` 2.1.1, MIT, with `assets/fonts/MIT-Phosphor.txt`
/// beside it, the same way the app ships its other fonts. No Dart package.
///
/// Code points are from that release's `src/regular/style.css`.
///
/// **The font is a subset holding only these glyphs, cut by hand.** The build's
/// icon tree-shaking did not touch it: measured on a release APK, Material's
/// icon font shipped at 6,960 bytes and the full Phosphor font at all 488,636.
/// Cut with the subsetter Flutter itself ships, which gave 1,712 bytes, and
/// checked by drawing all three on an Android 14 emulator beside a code point
/// outside the subset, which drew nothing.
///
/// **Adding an icon means re-cutting it**, from the upstream font, with every
/// code point below plus the new one:
///
/// ```sh
/// printf '%d %d %d' 0xe68e 0xe344 0xe102 \
///   | "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/font-subset" \
///       assets/fonts/Phosphor.ttf <upstream>/src/regular/Phosphor.ttf
/// ```
abstract final class PhosphorGlyphs {
  static const _family = 'Phosphor';

  /// `ph-users-three`: the audience score.
  static const usersThree = IconData(0xe68e, fontFamily: _family);

  /// `ph-newspaper`: the critics score.
  static const newspaper = IconData(0xe344, fontFamily: _family);

  /// `ph-buildings`: the studios.
  static const buildings = IconData(0xe102, fontFamily: _family);
}
