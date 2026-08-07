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

SnackBar assignResultToast({
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) =>
    SnackBar(
      content: Text(message),
      duration: assignToastDuration,
      // Explicit, and load-bearing: without it this toast never leaves.
      persist: false,
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );
