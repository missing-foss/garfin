// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// The one toast in Garfin that carries an action, and the one that would not
/// go away (#65).
///
/// **The cause is a framework default, not the duration.** `SnackBar.persist`
/// defaults to `action != null`, so *any* snackbar with an action stays until
/// something dismisses it — measured on Flutter 3.44.8 at more than an hour,
/// with a content-only control disappearing normally in the same harness. Every
/// other toast in the app is content-only, which is exactly why this was the
/// only one that stuck. The reported symptom had nothing to do with the
/// duration, and setting a duration alone does not fix it: the timer fires,
/// reads `persist`, and returns.
///
/// It is also **not** the accessibility path. Flutter used to keep an
/// action-bearing snackbar up while a screen reader was active, so the action
/// could not be snatched away on a timer; this version does not branch on
/// `accessibleNavigation` at all — measured, on and off, same result. Garfin
/// deliberately does not reimplement that branch: one code path for everyone,
/// and a screen-reader user who does not reach Undo in eight seconds still has
/// it on the Activity screen, where an entry stays undoable however old it is.
///
/// **Eight seconds**, the long end of Material's 4–10s, because this message
/// names a child, a count and a total and *then* asks for a decision.
///
/// The expiry is not a loss of function, and that is what makes it safe: Undo
/// here and Undo in Activity are the same act — a fresh forward write, never a
/// restore (ground rule 5). A button that outlives the moment it belonged to is
/// worse than one that expires, because tapping it an hour later writes against
/// a list that has moved on.
const assignToastDuration = Duration(seconds: 8);

/// [pending] is what it says while the verification is still in flight, and
/// [verified] builds the sentence once the count lands (#68).
///
/// The number arrives *into* the toast rather than gating it. The write takes
/// ~18 ms and does not grow; the count costs 19 ms when the child can see one
/// title and 538 ms when they can see 2000, measured on 10.11.11. Waiting for
/// it before saying anything left the parent watching a spinner for work that
/// had already happened.
///
/// If the count never lands — the request failed, or it is slower than the
/// eight seconds this toast lives for — the pending sentence stays. It is not a
/// placeholder for a number that is owed: it is true on its own, and the Kids
/// screen carries the verified count regardless.
SnackBar assignResultToast({
  required String pending,
  required String Function(Map<String, int> counts) verified,
  required Future<Map<String, int>> counts,
  required String undoLabel,
  required VoidCallback onUndo,
}) =>
    SnackBar(
      content:
          _FillingText(pending: pending, verified: verified, counts: counts),
      duration: assignToastDuration,
      // Explicit, and load-bearing: without it this toast never leaves.
      persist: false,
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );

class _FillingText extends StatelessWidget {
  const _FillingText({
    required this.pending,
    required this.verified,
    required this.counts,
  });

  final String pending;
  final String Function(Map<String, int> counts) verified;
  final Future<Map<String, int>> counts;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, int>>(
        future: counts,
        builder: (context, snapshot) {
          final data = snapshot.data;
          // An empty map is the repository's "asked, could not verify", which
          // is the same case as still waiting as far as what can be said.
          if (data == null || data.isEmpty) return Text(pending);
          return Text(verified(data));
        },
      );
}
