// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The Library's picked child does not follow the Kids overview. Seven places
/// invalidate the overview; each used to hand the Library a new child object,
/// and the grid refetched its whole window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  // A new object every time, as a re-fetched account is.
  JellyfinUser emma() => JellyfinUser(
        id: 'kid-1',
        name: 'Emma',
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: ['kids-emma'],
          blockedTags: [],
        ),
      );

  late FakeJellyfinServer server;

  /// While set, the Kids overview is reloading and has not answered yet.
  Completer<KidsOverview>? pendingReload;

  Future<ProviderContainer> build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 0, 'Items': <Object>[]});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        deviceIdentityProvider.overrideWithValue(const DeviceIdentity(deviceId: 'd', deviceName: 't')),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'), adapter: server),
        ),
        kidsRosterProvider(session).overrideWith(
          (ref) async => KidsRoster(
            shortlisted: [KidFace(user: emma(), avatarUrl: null)],
            withoutShortlist: const <UnshortlistedUser>[],
          ),
        ),
        kidsOverviewProvider(session).overrideWith((ref) {
          final reload = pendingReload;
          if (reload != null) return reload.future; // still loading
          return Future.value(KidsOverview(
            shortlisted: [KidSummary(user: emma(), birthYear: 2016)],
            withoutShortlist: const <UnshortlistedUser>[],
          ));
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test("invalidating the Kids overview does not refetch the child's Library", () async {
    final container = await build();
    container.read(pickingForProvider.notifier).select('kid-1');
    await container.read(kidsRosterProvider(session).future);
    await container.read(kidsOverviewProvider(session).future);
    final sub = container.listen(libraryControllerProvider(session), (_, _) {});
    addTearDown(sub.close);
    await container.read(libraryControllerProvider(session).future);
    expect(container.read(pickedChildProvider(session))?.id, 'kid-1');
    final before = server.callsTo('/Items');

    for (var i = 0; i < 3; i++) {
      container.invalidate(kidsOverviewProvider(session));
      await container.read(kidsOverviewProvider(session).future);
      await container.read(libraryControllerProvider(session).future);
    }

    expect(server.callsTo('/Items'), before);
  });

  // The loading case passes with the old overview-based child too: an
  // invalidated provider keeps its previous data while it refreshes, so
  // `.asData` still has it. The failure case below is the one that tells
  // them apart. Kept so a change to that refresh behaviour is caught here.
  test('while the Kids overview reloads, the child stays the child and nothing refetches', () async {
    final container = await build();
    container.read(pickingForProvider.notifier).select('kid-1');
    await container.read(kidsRosterProvider(session).future);
    await container.read(kidsOverviewProvider(session).future);
    final sub = container.listen(libraryControllerProvider(session), (_, _) {});
    addTearDown(sub.close);
    await container.read(libraryControllerProvider(session).future);
    final before = server.callsTo('/Items');

    pendingReload = Completer<KidsOverview>();
    addTearDown(() => pendingReload = null);
    container.invalidate(kidsOverviewProvider(session));
    // Read it, so the reload starts, and leave it loading.
    expect(container.read(kidsOverviewProvider(session)).isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(pickedChildProvider(session))?.id, 'kid-1',
        reason: 'not "Everyone" for as long as the overview is loading');
    await container.read(libraryControllerProvider(session).future);
    expect(server.callsTo('/Items'), before);
  });

  test('when the Kids overview fails to reload, the child stays the child and nothing refetches', () async {
    final container = await build();
    container.read(pickingForProvider.notifier).select('kid-1');
    await container.read(kidsRosterProvider(session).future);
    await container.read(kidsOverviewProvider(session).future);
    final sub = container.listen(libraryControllerProvider(session), (_, _) {});
    addTearDown(sub.close);
    await container.read(libraryControllerProvider(session).future);
    final before = server.callsTo('/Items');

    pendingReload = Completer<KidsOverview>();
    addTearDown(() => pendingReload = null);
    // Listened to, so the reload is not disposed before it fails.
    final overviewSub = container.listen(kidsOverviewProvider(session), (_, _) {});
    addTearDown(overviewSub.close);
    container.invalidate(kidsOverviewProvider(session));
    container.read(kidsOverviewProvider(session));
    pendingReload!.completeError(Exception('the counts request failed'));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(kidsOverviewProvider(session)).hasError, isTrue);

    expect(container.read(pickedChildProvider(session))?.id, 'kid-1',
        reason: 'a failed overview is not a reason to show Everyone');
    await container.read(libraryControllerProvider(session).future);
    expect(server.callsTo('/Items'), before);
  });

  group('equality reads every field', () {
    // Equality now decides whether anything hears about a re-fetched account,
    // so a field left out of it is a parent's change that never reaches the
    // screens. Each variant differs from the base in exactly one field.
    UserPolicy policy({
      bool isAdministrator = false,
      bool isDisabled = false,
      List<String> allowedTags = const ['kids-emma'],
      List<String> blockedTags = const [],
      int? maxParentalRating = 10,
      int? maxParentalSubRating,
      List<AccessSchedule> accessSchedules = const [],
      bool enableAllFolders = true,
      List<String> enabledFolders = const [],
    }) =>
        UserPolicy(
          isAdministrator: isAdministrator,
          isDisabled: isDisabled,
          allowedTags: allowedTags,
          blockedTags: blockedTags,
          maxParentalRating: maxParentalRating,
          maxParentalSubRating: maxParentalSubRating,
          accessSchedules: accessSchedules,
          enableAllFolders: enableAllFolders,
          enabledFolders: enabledFolders,
        );
    JellyfinUser user({String name = 'Emma', UserPolicy? withPolicy, String? primaryImageTag}) =>
        JellyfinUser(id: 'kid-1', name: name, policy: withPolicy ?? policy(), primaryImageTag: primaryImageTag);

    test('the same account, read again, is the same user', () {
      expect(user(), user());
      expect(user().hashCode, user().hashCode);
      expect(emma(), emma());
    });

    final variants = <String, JellyfinUser>{
      'isAdministrator': user(withPolicy: policy(isAdministrator: true)),
      'isDisabled': user(withPolicy: policy(isDisabled: true)),
      'allowedTags': user(withPolicy: policy(allowedTags: ['kids-leo'])),
      'blockedTags': user(withPolicy: policy(blockedTags: ['horror'])),
      'maxParentalRating': user(withPolicy: policy(maxParentalRating: 13)),
      'maxParentalSubRating': user(withPolicy: policy(maxParentalSubRating: 1)),
      'accessSchedules': user(withPolicy: policy(accessSchedules: const [
        AccessSchedule(dayOfWeek: 'Everyday', startHour: 8, endHour: 20),
      ])),
      'enableAllFolders': user(withPolicy: policy(enableAllFolders: false)),
      'enabledFolders': user(withPolicy: policy(enabledFolders: ['films'])),
      'name': user(name: 'Emma B'),
      'primaryImageTag': user(primaryImageTag: 'abc123'),
    };
    for (final MapEntry(key: field, value: variant) in variants.entries) {
      test('a change to $field is a different user', () {
        expect(variant, isNot(user()), reason: field);
      });
    }
  });
}
