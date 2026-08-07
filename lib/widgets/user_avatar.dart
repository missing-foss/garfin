// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A Jellyfin user's picture, or their initial when there isn't one.
///
/// Extracted from `KidCard` for #79. Both lists on the Kids screen show the
/// same people from the same server, and only one of them was showing pictures:
/// the shortlisted kids had this logic and the unmanaged accounts had a bare
/// `CircleAvatar` with a letter — not as a fallback, as the only branch. In a
/// household where the unmanaged accounts are Mum, Dad and a guest, that is
/// three identical grey circles directly under a row of distinguishable
/// children.
///
/// One widget rather than two copies, because the *fallback* behaviour is the
/// part that has to match and is the part most easily got subtly wrong.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.avatarUrl,
    this.radius = 24,
  });

  final String name;

  /// Null when the user has no picture — measured as key-*absence* in the
  /// server's response rather than a null value, so it is not a guess. Asking
  /// anyway would put a 404 behind every initial.
  final String? avatarUrl;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = initialFor(name);

    if (avatarUrl == null) {
      return CircleAvatar(radius: radius, child: Text(initial));
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        // The initial while loading *and* on error, so a picture that never
        // arrives degrades to the same thing as no picture rather than a blank
        // circle.
        placeholder: (_, _) => CircleAvatar(radius: radius, child: Text(initial)),
        errorWidget: (_, _, _) =>
            CircleAvatar(radius: radius, child: Text(initial)),
      ),
    );
  }
}

/// The letter shown when there is no picture.
///
/// `characters.first`, not `name[0]`: a name beginning with an emoji or any
/// non-BMP character would otherwise be cut through the middle of a surrogate
/// pair and render as a replacement box.
String initialFor(String name) =>
    name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
