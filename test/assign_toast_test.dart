// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/widgets/assign_result_toast.dart';

/// The assign toast, which never went away (#65).
///
/// Nothing in this repo tested a `SnackBar` before, which is how a toast that
/// stayed on screen indefinitely shipped: the bug is invisible to every
/// repository- and screen-level test, because the write it reports succeeded.
///
/// **Every assertion here pumps a control first.** The first attempt at
/// measuring this reported that a content-only snackbar also never disappears,
/// which is false — one enormous `pump` fires the dismissal timer but never
/// runs the exit animation, so the widget is still in the tree. A test that
/// waits and finds something present is indistinguishable from a test that
/// never waited properly.
void main() {
  /// Shows [bar], waits [wait], and answers whether it is still on screen.
  ///
  /// `pumpAndSettle` on both sides: once to finish the entrance, once to let
  /// the exit animation actually run after the timer fires.
  Future<bool> stillThereAfter(
    WidgetTester tester,
    SnackBar bar,
    Duration wait,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          }),
        ),
      ),
    );
    ScaffoldMessenger.of(ctx).showSnackBar(bar);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'control: it must be on screen before the wait means anything');

    await tester.pump(wait);
    await tester.pumpAndSettle();
    return find.byType(SnackBar).evaluate().isNotEmpty;
  }

  SnackBar toast({VoidCallback? onUndo, Future<Map<String, int>>? counts}) =>
      assignResultToast(
        pending: 'Shared with Emma',
        verified: (c) => 'Emma now sees ${c['kid-1']} of 40',
        // #68: the count arrives after the toast does. A future that never
        // completes is the honest default here — it is what a slow server looks
        // like, and it keeps these tests about the toast's lifetime.
        counts: counts ?? Completer<Map<String, int>>().future,
        undoLabel: 'Undo',
        onUndo: onUndo ?? () {},
      );

  testWidgets('it goes away', (tester) async {
    // The bug, in one line.
    expect(
      await stillThereAfter(tester, toast(), const Duration(seconds: 12)),
      isFalse,
    );
  });

  testWidgets('it is still there a second before its time', (tester) async {
    // Without this, `duration: Duration.zero` would pass the test above while
    // making Undo unreachable — the opposite defect, and just as silent.
    expect(
      await stillThereAfter(
        tester,
        toast(),
        assignToastDuration - const Duration(seconds: 1),
      ),
      isTrue,
    );
  });

  testWidgets('Undo is on it, and does the thing', (tester) async {
    var undone = false;
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          }),
        ),
      ),
    );
    ScaffoldMessenger.of(ctx)
        .showSnackBar(toast(onUndo: () => undone = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(undone, isTrue);
  });

  // These two are the assumption Garfin is built on rather than tests of
  // Garfin, so that if a future Flutter changes the default, they fail and name
  // the sentence in `assign_result_toast.dart` that stopped being true.
  //
  // **One per test, deliberately.** Showing both in a single test passed the
  // control and then failed: `pumpWidget` reuses the element tree, so the
  // `ScaffoldMessenger` survives and the second snackbar queues *behind* the
  // first — and since the first is the persistent one, what the second half
  // then measured was the first toast still standing. Exactly the kind of
  // confound the controls here exist to catch.
  testWidgets('framework default: an action makes a toast persist',
      (tester) async {
    // Measured on 3.44.8: `SnackBar.persist` defaults to `action != null`, so
    // this one stays indefinitely — an hour, in the probe.
    expect(
      await stillThereAfter(
        tester,
        SnackBar(
          content: const Text('x'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
        const Duration(minutes: 5),
      ),
      isTrue,
      reason: 'if this is now false, persist no longer defaults to '
          'action != null and the comment in assign_result_toast.dart is stale',
    );
  });

  testWidgets('framework control: a content-only toast dismisses',
      (tester) async {
    expect(
      await stillThereAfter(
        tester,
        const SnackBar(content: Text('x')),
        const Duration(minutes: 5),
      ),
      isFalse,
      reason: 'the control: content-only toasts have always dismissed, and '
          'without it "it stayed" cannot be told from "the harness never '
          'waited properly"',
    );
  });

  group('the count arrives after the toast (#68)', () {
    testWidgets('it says what is true before the number is known',
        (tester) async {
      // The write is done in ~18 ms; the count costs 19 ms to 538 ms depending
      // on how much the child can already see. The old code awaited the count
      // before closing the sheet, so the parent watched a spinner for work
      // that had already happened.
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            }),
          ),
        ),
      );
      final counts = Completer<Map<String, int>>();
      ScaffoldMessenger.of(ctx).showSnackBar(toast(counts: counts.future));
      await tester.pumpAndSettle();

      expect(find.text('Shared with Emma'), findsOneWidget);
      expect(find.textContaining('now sees'), findsNothing);

      counts.complete(<String, int>{'kid-1': 13});
      await tester.pumpAndSettle();

      expect(find.text('Emma now sees 13 of 40'), findsOneWidget);
      expect(find.text('Shared with Emma'), findsNothing);
    });

    testWidgets('a verification that fails leaves a true sentence, not a gap',
        (tester) async {
      // The repository answers an empty map rather than throwing, because this
      // future is handed to the UI unawaited and an unawaited failure is a
      // crash report for a *successful* write.
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            }),
          ),
        ),
      );
      ScaffoldMessenger.of(ctx).showSnackBar(
        toast(counts: Future<Map<String, int>>.value(const <String, int>{})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared with Emma'), findsOneWidget);
    });

    testWidgets('a count slower than the toast does not resurrect it',
        (tester) async {
      // Eight seconds is the toast's life (#65). A count that lands afterwards
      // has nowhere to go, and must not throw on a disposed element.
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            }),
          ),
        ),
      );
      final counts = Completer<Map<String, int>>();
      ScaffoldMessenger.of(ctx).showSnackBar(toast(counts: counts.future));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget, reason: 'control');

      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      counts.complete(<String, int>{'kid-1': 13});
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  test('every action-bearing toast in lib/ sets persist', () {
    // The guard for the *next* one. This bug was not a regression — it was the
    // first toast in the app to carry an action, and the default did the rest.
    // Any future one inherits the same trap, so the rule is asserted rather
    // than left in a comment: if you add an action, say what persist is.
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('l10n/gen'))
        .map((f) => f.readAsStringSync());

    var actions = 0;
    var persists = 0;
    for (final source in sources) {
      actions += 'SnackBarAction('.allMatches(source).length;
      persists += 'persist:'.allMatches(source).length;
    }

    expect(actions, greaterThan(0), reason: 'control: the grep still matches');
    expect(persists, greaterThanOrEqualTo(actions),
        reason: 'a SnackBar with an action that does not set persist will '
            'never disappear — see #65');
  });
}
