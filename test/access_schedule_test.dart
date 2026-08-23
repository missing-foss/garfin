// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/widgets/kid_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Access schedules — the other half of what Jellyfin enforces (#49).
///
/// Two measured details do the damage if missed: the hours are **floats**, so
/// an int reader turns 08:30 into 08:00 in the direction of *more* access; and
/// `DayOfWeek` has **ten** values, not seven, of which `Everyday` is the one a
/// parent most often picks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> policyJson(List<Map<String, dynamic>> schedules) =>
      <String, dynamic>{
        'IsAdministrator': false,
        'IsDisabled': false,
        'AccessSchedules': schedules,
      };

  group('parsing', () {
    test('the hours are floats, and half past is not an hour', () {
      // Measured: 8.5 is 08:30 and 20.25 is 20:15. Truncating would hand back
      // half an hour of access nobody granted.
      final policy = UserPolicy.fromJson(policyJson([
        {'DayOfWeek': 'Everyday', 'StartHour': 8.5, 'EndHour': 20.25},
      ]));

      expect(policy.accessSchedules.single.startHour, 8.5);
      expect(policy.accessSchedules.single.endHour, 20.25);
      expect(formatScheduleHour(8.5), '08:30');
      expect(formatScheduleHour(20.25), '20:15');
      expect(formatScheduleHour(0), '00:00');
      expect(formatScheduleHour(23.75), '23:45');
    });

    test('an integer hour is read as one, not dropped', () {
      // JSON gives whole numbers as ints, so a schedule of exactly 9 to 17
      // arrives typed differently from one of 8.5 to 20.25.
      final policy = UserPolicy.fromJson(policyJson([
        {'DayOfWeek': 'Monday', 'StartHour': 9, 'EndHour': 17},
      ]));

      expect(policy.accessSchedules.single.startHour, 9.0);
      expect(formatScheduleHour(policy.accessSchedules.single.endHour), '17:00');
    });

    test('all ten day values survive, including the three that are not days',
        () {
      // The enum is the seven days plus Everyday, Weekday and Weekend. A reader
      // that assumed seven would drop the commonest configuration.
      const days = [
        'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
        'Saturday', 'Everyday', 'Weekday', 'Weekend',
      ];
      final policy = UserPolicy.fromJson(policyJson([
        for (final day in days)
          {'DayOfWeek': day, 'StartHour': 1, 'EndHour': 2},
      ]));

      expect(policy.accessSchedules.map((s) => s.dayOfWeek), days);
    });

    test('no schedules at all is empty, not null', () {
      expect(
        UserPolicy.fromJson(<String, dynamic>{
          'IsAdministrator': false,
          'IsDisabled': false,
        }).accessSchedules,
        isEmpty,
      );
      expect(UserPolicy.fromJson(policyJson([])).accessSchedules, isEmpty);
    });

    test('a malformed entry drops out without taking the others', () {
      final policy = UserPolicy.fromJson(policyJson([
        {'DayOfWeek': 'Everyday', 'StartHour': 8, 'EndHour': 20},
        {'DayOfWeek': 'Everyday'}, // no hours
        {'StartHour': 1, 'EndHour': 2}, // no day
      ]));

      expect(policy.accessSchedules, hasLength(1));
      expect(policy.accessSchedules.single.dayOfWeek, 'Everyday');
    });
  });

  group('on the card', () {
    KidSummary kid(List<AccessSchedule> schedules) => KidSummary(
          user: JellyfinUser(
            id: 'k1',
            name: 'Emma',
            policy: UserPolicy(
              isAdministrator: false,
              isDisabled: false,
              allowedTags: const ['kids-emma'],
              accessSchedules: schedules,
            ),
          ),
          visibleCount: 12,
          libraryTotal: 40,
        );

    Future<void> pump(WidgetTester tester, KidSummary summary) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: KidCard(
                kid: summary,
                session: const AuthSession(
                  serverUrl: 'http://host:8096',
                  accessToken: 'token',
                  userId: 'admin-1',
                  userName: 'Parent',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no schedule is said, not left blank', (tester) async {
      // A blank line where other children show times would read as "restricted,
      // and Garfin did not say when" — the opposite of what it means.
      await pump(tester, kid(const []));
      expect(find.text('Can watch at any time of day.'), findsOneWidget);
    });

    testWidgets('a window says whose clock it is on', (tester) async {
      // Measured: the server's offset is not exposed anywhere, so these hours
      // cannot be converted and must not look converted.
      await pump(tester, kid(const [
        AccessSchedule(dayOfWeek: 'Everyday', startHour: 8.5, endHour: 20.0),
      ]));

      expect(find.textContaining('Every day 08:30–20:00'), findsOneWidget);
      expect(find.textContaining("the server's hours"), findsOneWidget);
    });

    testWidgets('Everyday reads as one line rather than seven', (tester) async {
      await pump(tester, kid(const [
        AccessSchedule(dayOfWeek: 'Everyday', startHour: 8, endHour: 20),
      ]));

      expect(find.textContaining('Every day'), findsOneWidget);
      expect(find.textContaining('Monday'), findsNothing);
    });

    testWidgets('a named day is named in the reader\'s language',
        (tester) async {
      await pump(tester, kid(const [
        AccessSchedule(dayOfWeek: 'Saturday', startHour: 9, endHour: 12),
      ]));

      expect(find.textContaining('Saturday 09:00–12:00'), findsOneWidget);
    });

    testWidgets('a value from a later server renders as itself', (tester) async {
      // The server rejects an unknown day with 400, so this should not arrive
      // — but rendering it as itself beats throwing or silently dropping a
      // restriction the parent set.
      await pump(tester, kid(const [
        AccessSchedule(dayOfWeek: 'Fortnightly', startHour: 9, endHour: 12),
      ]));

      expect(find.textContaining('Fortnightly 09:00–12:00'), findsOneWidget);
    });

    testWidgets('several windows are all shown', (tester) async {
      await pump(tester, kid(const [
        AccessSchedule(dayOfWeek: 'Weekday', startHour: 16, endHour: 19),
        AccessSchedule(dayOfWeek: 'Weekend', startHour: 9, endHour: 20.5),
      ]));

      expect(find.textContaining('Weekdays 16:00–19:00'), findsOneWidget);
      expect(find.textContaining('Weekends 09:00–20:30'), findsOneWidget);
    });
  });
}
