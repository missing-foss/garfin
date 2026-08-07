// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

import 'support/fake_jellyfin_server.dart';

/// What ground rule 1's last-item warning counts, and what it must not count.
///
/// Measured for #53: a label written to one **series** is inherited by its
/// seasons and episodes — they report it, and `tags=` matches them. One write
/// to one six-episode series answers 1 for `Movie,Series,BoxSet`, 2 for
/// `Season`, 6 for `Episode` and 9 unfiltered.
///
/// So the item types here are a safety property. Widen them and a single series
/// contributes nine items instead of one, `count <= 1` stops being reachable in
/// any library containing a series, and the hard warning that stops a parent
/// blanking a child's view **silently never fires again**. Nothing about that
/// failure is visible: no error, no crash, just a warning that stopped
/// happening.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJellyfinServer server;
  late JellyfinApi api;

  setUp(() {
    server = FakeJellyfinServer();
    api = JellyfinApiFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    ).create(baseUrl: 'http://host:8096');
  });

  Map<String, dynamic> lastQuery() => server.requests.last.queryParameters;

  test('the count asks only about the types a parent hands over', () async {
    server.fallback(json: <String, dynamic>{'TotalRecordCount': 3});

    await api.taggedItemCount(userId: 'admin-1', tags: const ['kids-emma']);

    final types = (lastQuery()['IncludeItemTypes'] as String).split(',');
    expect(types.toSet(), {'Movie', 'Series', 'BoxSet'});
  });

  test('and never about episodes or seasons, which inherit the series\' label',
      () async {
    server.fallback(json: <String, dynamic>{'TotalRecordCount': 3});

    await api.taggedItemCount(userId: 'admin-1', tags: const ['kids-emma']);

    final types = (lastQuery()['IncludeItemTypes'] as String).split(',');
    expect(types, isNot(contains('Episode')),
        reason: 'one series would contribute six of these, and the last-item '
            'warning would stop firing');
    expect(types, isNot(contains('Season')));
  });

  test('the type filter is sent at all', () async {
    // Unfiltered, the same single write answers 9 rather than 1.
    server.fallback(json: <String, dynamic>{'TotalRecordCount': 3});

    await api.taggedItemCount(userId: 'admin-1', tags: const ['kids-emma']);

    expect(lastQuery().containsKey('IncludeItemTypes'), isTrue);
    expect(lastQuery()['tags'], 'kids-emma');
    expect(lastQuery()['Limit'], 0, reason: 'a count, not a page of items');
  });
}
