// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/kids_repository.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The vocabulary queries fall back to empty when the server fails them, so
/// the screen stays up. Each fallback is logged by type, so a broken endpoint
/// is distinguishable from an empty server.
void main() {
  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => sub.cancel());

  ProviderContainer failing() {
    const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');
    final server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{}, status: 500);
    final c = ProviderContainer(
      overrides: [
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: server),
        ),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  List<String> messages() => [for (final r in records) r.message];

  for (final (name, read, logged) in <(String, Future<Object?> Function(ProviderContainer), String)>[
    (
      'the ratings ladder',
      (c) => c.read(parentalRatingLadderProvider(session).future),
      'parental ratings unavailable',
    ),
    (
      'the country list',
      (c) => c.read(countriesProvider(session).future),
      'countries unavailable',
    ),
    (
      'the genres',
      (c) => c.read(libraryGenresProvider(session).future),
      'genres unavailable',
    ),
    (
      'the decades',
      (c) => c.read(libraryDecadesProvider(session).future),
      'years unavailable',
    ),
  ]) {
    test('$name falls back to empty, and says why', () async {
      await read(failing());

      final line = messages().where((m) => m.contains(logged));
      expect(line, hasLength(1), reason: messages().join('\n'));
      expect(line.single, contains('JellyfinException'),
          reason: 'the type, as at every other log site');
    });
  }

  test('a search name that cannot be resolved falls back, and says why',
      () async {
    final c = failing();
    c.read(libraryFiltersProvider.notifier).set(const LibraryFilters(
          searchTerm: 'Tautou',
          searchScope: SearchScope.castAndCrew,
        ));

    final resolved =
        await c.read(resolvedLibraryFiltersProvider(session).future);

    expect(resolved.resolvedSearchValue, isNull);
    final line = messages().where((m) => m.contains('search name unresolved'));
    expect(line, hasLength(1), reason: messages().join('\n'));
    expect(line.single, contains('JellyfinException'));
  });

  test("the Kids screen's ratings ladder falls back, and says why", () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');
    final server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{}, status: 500);
    final repository = KidsRepository(
      api: JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: session.serverUrl),
      birthYears: BirthYearStore(await SharedPreferences.getInstance()),
      serverUrl: session.serverUrl,
    );

    await repository.load(
      const KidsRoster(shortlisted: [], withoutShortlist: []),
    );

    final line =
        messages().where((m) => m.contains('parental ratings unavailable'));
    expect(line, hasLength(1), reason: messages().join('\n'));
    expect(line.single, contains('JellyfinException'));
  });
}
