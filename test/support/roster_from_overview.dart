// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/providers/kids_providers.dart';

/// The roster a test's overridden Kids overview implies.
///
/// The Library takes its picked child from the roster, the cheap request,
/// while most tests describe the children once, as an overview. This keeps
/// those tests describing them once: the roster is the overview's faces.
Override rosterFromOverview(AuthSession session) =>
    kidsRosterProvider(session).overrideWith((ref) async {
      final overview = await ref.watch(kidsOverviewProvider(session).future);
      return KidsRoster(
        shortlisted: [
          for (final kid in overview.shortlisted) KidFace(user: kid.user, avatarUrl: kid.avatarUrl),
        ],
        withoutShortlist: overview.withoutShortlist,
      );
    });
