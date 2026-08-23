// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../repositories/session_verifier.dart';

/// Long enough to outlive [sessionSettle] and still be read (#70).
///
/// The read-back cannot land before three seconds have passed, so the default
/// four-second snackbar would spend its whole life on the pending sentence and
/// expire at the moment it had something to add. Eight seconds — the long end
/// of Material's 4–10s, the same as `assignToastDuration` and for the same
/// reason — leaves about five seconds with the answer on screen.
///
/// **Bounded below by `sessionSettle`.** Raise that and this has to move too,
/// or the verification becomes work whose result nobody sees.
const sessionToastDuration = Duration(seconds: 8);

/// A toast that starts by saying what Garfin sent and finishes by saying what
/// happened (#70).
///
/// [pending] is true when it appears — the command *was* sent — and [resolved]
/// replaces it if the read-back contradicts or confirms it in a way worth
/// saying. Resolving to `null` keeps the pending sentence, which is what an
/// unverifiable outcome deserves: nothing was learned, so nothing changes.
///
/// The outcome arrives *into* the toast rather than gating it, which is #68's
/// shape and its reasoning too — the command has already finished, and a
/// spinner over finished work is exactly what #68 took off the assign path.
///
/// No action, so no `persist` to set: the framework defaults it to
/// `action != null`, which is what kept the one action-bearing toast in the app
/// on screen forever (#65). Content-only toasts were never affected.
SnackBar sessionResultToast({
  required String pending,
  required Future<String?> resolved,
}) =>
    SnackBar(
      content: _FillingText(pending: pending, resolved: resolved),
      duration: sessionToastDuration,
    );

class _FillingText extends StatelessWidget {
  const _FillingText({required this.pending, required this.resolved});

  final String pending;
  final Future<String?> resolved;

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: resolved,
        // Still waiting and "resolved to nothing worth saying" are the same
        // case here, and both are already covered by the sentence on screen.
        builder: (context, snapshot) => Text(snapshot.data ?? pending),
      );
}
