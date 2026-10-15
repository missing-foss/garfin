// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

/// A Jellyfin image fetched and decoded at the size it is shown, rather than
/// at the server's full resolution.
///
/// A 1000×1500 poster decodes to 6 MB, so a grid of them fills Flutter's
/// 100 MB image cache after seventeen and then churns. Jellyfin resizes on its
/// side when the URL carries `maxWidth`, so the download shrinks too, and
/// `memCacheWidth` holds the decoded bitmap at the same width whatever the
/// server sends back.
class ServerImage extends StatelessWidget {
  const ServerImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.aspectRatio = 2 / 3,
    this.width,
    this.height,
  });

  /// The image URL as built today; `maxWidth` is appended to it.
  final String url;

  /// Shown while loading and when the image fails.
  final Widget placeholder;

  /// The image's own width over height: 2/3 for a poster, 1 for an avatar.
  /// It decides how wide the image must be to cover its slot.
  final double aspectRatio;

  /// A fixed size, when the slot has one; otherwise the layout's.
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final px = coverWidthPx(
          width ?? constraints.maxWidth,
          height ?? constraints.maxHeight,
          aspectRatio,
          MediaQuery.devicePixelRatioOf(context),
        );
        return CachedNetworkImage(
          imageUrl: px == null ? url : withMaxWidth(url, px),
          memCacheWidth: px,
          width: width,
          height: height,
          fit: BoxFit.cover,
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => placeholder,
        );
      },
    );
  }
}

/// Width steps, in pixels: slots of nearly the same width share one request
/// and one cache entry instead of one each.
const int imageWidthStep = 120;

/// The pixel width an image of [aspectRatio] needs to cover a slot of
/// [width]×[height] logical pixels at [devicePixelRatio], rounded up to a
/// step; null when the slot has no finite size to measure.
///
/// Covering scales the image until it fills both sides, so its width must
/// reach the slot's width and the slot's height times the image's aspect.
int? coverWidthPx(double width, double height, double aspectRatio, double devicePixelRatio) {
  final w = width.isFinite ? width : 0.0;
  final h = height.isFinite ? height * aspectRatio : 0.0;
  final logical = math.max(w, h);
  if (logical <= 0) return null;
  final px = logical * devicePixelRatio;
  return (px / imageWidthStep).ceil() * imageWidthStep;
}

/// [url] with `maxWidth=px` added to its query.
String withMaxWidth(String url, int px) =>
    '$url${url.contains('?') ? '&' : '?'}maxWidth=$px';
