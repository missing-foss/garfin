// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/screens/about_screen.dart';
import 'package:garfin/widgets/garfin_tank.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The egg, and the acceptance the deferral asked for.
///
/// The reason this was put off rather than stubbed was that "a tap counter
/// that opens nothing is dead code no test can cover". So the counter and the
/// thing it opens are covered together, and the one rule is asserted in both
/// directions against a world built for the purpose rather than a random one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAbout(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AboutScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder theMark() => find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == 'Garfin',
      );

  Future<void> tapMark(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(theMark().first);
      await tester.pump();
    }
  }

  /// One tick, without letting the ticker run forever — `pumpAndSettle` never
  /// settles against a running `Ticker`.
  Future<void> step(WidgetTester tester, {int frames = 1}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  GarfinTankState tank(WidgetTester tester) =>
      tester.state<GarfinTankState>(find.byType(GarfinTank));

  group('finding it', () {
    testWidgets('four taps open nothing', (tester) async {
      await pumpAbout(tester);
      await tapMark(tester, 4);
      expect(find.byType(GarfinTank), findsNothing);
    });

    testWidgets('the fifth opens it', (tester) async {
      await pumpAbout(tester);
      await tapMark(tester, 5);
      await tester.pump();
      expect(find.byType(GarfinTank), findsOneWidget);
      await step(tester);
    });

    testWidgets('leaving puts About back exactly as it was', (tester) async {
      await pumpAbout(tester);
      // What About showed before, to compare against after.
      final before = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();

      await tapMark(tester, 5);
      await tester.pump();
      expect(find.byType(GarfinTank), findsOneWidget);
      await step(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(GarfinTank), findsNothing);
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList(),
        before,
        reason: 'About must be what it was before the egg was opened',
      );
    });
  });

  group('the one rule', () {
    /// The tank with a world of exactly one circle, placed on the fish.
    Future<GarfinTankState> tankWithOne(
      WidgetTester tester, {
      required double radius,
    }) async {
      await tester.pumpWidget(
        const MaterialApp(home: GarfinTank(seed: 1)),
      );
      await step(tester);
      final state = tank(tester);
      state.drifters
        ..clear()
        ..add(TankDrifter(
          position: state.player,
          velocity: Offset.zero,
          radius: radius,
          colour: const Color(0xFFEADDFF),
        ));
      return state;
    }

    testWidgets('something smaller is eaten, and you grow', (tester) async {
      final state = await tankWithOne(tester, radius: 5);
      final before = state.playerRadius;
      final eaten = state.drifters.single;

      await step(tester, frames: 2);

      expect(state.playerRadius, greaterThan(before));
      expect(identical(state.drifters.single, eaten), isFalse,
          reason: 'the circle it ate is gone, replaced by a new one');
      await step(tester);
    });

    testWidgets('something bigger deflects you, and you shrink',
        (tester) async {
      final state = await tankWithOne(tester, radius: 60);
      final before = state.playerRadius;
      final at = state.player;

      await step(tester, frames: 2);

      expect(state.playerRadius, lessThan(before));
      expect(state.player, isNot(at), reason: 'it pushed the fish away');
      await step(tester);
    });

    testWidgets('shrinking never ends it', (tester) async {
      final state = await tankWithOne(tester, radius: 80);
      await step(tester, frames: 60);

      expect(state.playerRadius, greaterThan(0),
          reason: 'there is no fail state; the fish cannot vanish');
      expect(find.byType(GarfinTank), findsOneWidget);
      await step(tester);
    });
  });

  group('the feel of it', () {
    /// An empty tank. The measurements below are about the fish and the
    /// finger, and fourteen drifting circles would bounce it mid-measurement.
    Future<GarfinTankState> emptyTank(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: GarfinTank(seed: 1)));
      await step(tester);
      final state = tank(tester);
      state.drifters.clear();
      return state;
    }

    testWidgets('the fish closes half the gap in one half-life',
        (tester) async {
      final state = await emptyTank(tester);
      final from = state.player;
      const to = Offset(700, 500);
      final gap = (to - from).distance;

      await tester.tapAt(to);
      // Exactly one half-life, so the assertion is the constant's own claim
      // rather than a number that happened to feel right.
      await tester.pump(const Duration(milliseconds: 45));

      final covered = (state.player - from).distance / gap;
      expect(covered, greaterThan(0.40),
          reason: 'the old easing covered 11% here, and was reported as the '
              'fish being hard to move');
      expect(covered, lessThan(0.60));
      await step(tester);
    });

    testWidgets('and still trails rather than sticking to the finger',
        (tester) async {
      final state = await emptyTank(tester);
      const to = Offset(700, 500);

      await tester.tapAt(to);
      await tester.pump(const Duration(milliseconds: 16));

      expect(state.player, isNot(to),
          reason: 'a fish welded to the fingertip is not a fish');
      await step(tester);
    });
  });

  group('there is always something to eat, and something to fear', () {
    /// The radii of many spawns at a chosen size of fish.
    ///
    /// A distribution, sampled directly, rather than inferred from playing:
    /// a test that reached this by eating circles would be asserting about
    /// whatever the seed put in the way.
    Future<List<double>> radiiAt(WidgetTester tester, double player) async {
      await tester.pumpWidget(const MaterialApp(home: GarfinTank(seed: 7)));
      await step(tester);
      final state = tank(tester)..drifters.clear();
      state.playerRadius = player;
      final radii = [for (var i = 0; i < 600; i++) state.spawn().radius];
      await step(tester);
      return radii;
    }

    double shareBelow(List<double> radii, double player) =>
        radii.where((r) => r < player).length / radii.length;

    testWidgets('the opening is not thin', (tester) async {
      // At the starting radius the old draw left 39% of the tank edible —
      // about five circles of fourteen, each worth +2 on a radius of 26.
      final radii = await radiiAt(tester, 26);

      expect(shareBelow(radii, 26), greaterThan(0.50));
    });

    testWidgets('and the endgame is not empty', (tester) async {
      // The half nobody reported and the tank was worse at: the old draw
      // topped out at radius 54, so a fish past that could not meet anything
      // bigger than itself and the one rule quietly stopped applying.
      final radii = await radiiAt(tester, 80);

      final threats = 1 - shareBelow(radii, 80);
      expect(threats, greaterThan(0.20),
          reason: 'a fish that cannot lose is not playing');
      expect(shareBelow(radii, 80), greaterThan(0.40),
          reason: 'and it must still have something to chase');
    });

    testWidgets('neither end of the size range breaks the rule',
        (tester) async {
      // The clamps are the risk: an edible circle rounded up past the fish, or
      // a threat rounded down under it, would invert the rule at the extremes.
      for (final player in const [12.0, 90.0]) {
        final radii = await radiiAt(tester, player);
        expect(radii.every((r) => r != player), isTrue);
        expect(shareBelow(radii, player), greaterThan(0.40),
            reason: 'something to eat at radius $player');
        expect(1 - shareBelow(radii, player), greaterThan(0.10),
            reason: 'something to fear at radius $player');
      }
    });
  });

  testWidgets('the egg builds no Text at all', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GarfinTank(seed: 1)));
    await step(tester, frames: 5);

    // The property that keeps this at zero l10n surface. A single word here
    // would be a hardcoded UI string, or a catalogue entry in two languages
    // for a joke — and it is what the no-fail-state design exists to avoid.
    expect(find.byType(Text), findsNothing);
    await step(tester);
  });
}
