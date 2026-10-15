// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/providers/assign_sheet_controller.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The assign sheet's apply flow, driven without a widget: no pump, no fake
/// clock, and the dialogs answered by a host that records what it was asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');

  const emma = JellyfinUser(
    id: 'kid-1',
    name: 'Emma',
    policy: UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
      blockedTags: [],
    ),
  );
  const film = LibraryItem(
    id: 'film-1',
    name: 'Paddington',
    type: 'Movie',
    tags: <String>[],
  );
  const sequel = LibraryItem(
    id: 'film-2',
    name: 'Paddington 2',
    type: 'Movie',
    tags: <String>[],
  );
  const boxSet = LibraryItem(
    id: 'set-1',
    name: 'Paddington Collection',
    type: 'BoxSet',
    tags: <String>[],
  );
  const paddingtons =
      CollectionSet(collection: boxSet, members: [film, sequel]);

  // Emma does not have it yet; the parent switches her on.
  const row = AssignRow(
    child: emma,
    label: 'kids-emma',
    hasLabel: false,
    visibleCount: 3,
    libraryTotal: 10,
  );

  late FakeJellyfinServer server;

  setUp(() {
    server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});
    for (final id in ['film-1', 'film-2', 'set-1']) {
      server.onQuery(
        '/Users/admin-1/Items/$id',
        (_) => true,
        json: <String, dynamic>{'Id': id, 'Name': id, 'Tags': <String>[]},
      );
    }
  });

  Iterable<String> posts() =>
      server.requests.where((r) => r.method == 'POST').map((r) => r.path);

  /// A container with the sheet's controller for [item] kept alive, and every
  /// state it passes through.
  Future<
      ({
        AssignSheetController controller,
        List<AssignSheetState> states,
        ProviderContainer container,
      })> start(
    LibraryItem item, {
    Future<CollectionSet> Function()? set,
    CollectionIndex index = const CollectionIndex.empty(),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: server),
        ),
        if (set != null)
          collectionSetProvider(
            const CollectionRequest(session: session, collection: boxSet),
          ).overrideWith((ref) => set()),
        collectionIndexProvider(session).overrideWith((ref) async => index),
      ],
    );
    addTearDown(c.dispose);
    final provider = assignSheetControllerProvider(
      AssignRequest(session: session, item: item),
    );
    final states = <AssignSheetState>[];
    c.listen(provider, (_, next) => states.add(next));
    final controller = c.read(provider.notifier)..toggle(emma.id, true);
    return (controller: controller, states: states, container: c);
  }

  test('a toggle becomes the write it implies, and nothing is sent', () async {
    final (:controller, :states, container: _) = await start(film);

    final diff = states.last.diffFrom([row]);
    expect(diff.changes.single.adding, isTrue);
    expect(diff.changes.single.child, emma);
    expect(server.requests, isEmpty, reason: 'ground rule 1: no write on toggle');
  });

  test('the pending toggles go when the sheet does', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    final provider = assignSheetControllerProvider(
      const AssignRequest(session: session, item: film),
    );

    final open = c.listen(provider, (_, _) {});
    c.read(provider.notifier).toggle(emma.id, true);
    expect(c.read(provider).pending, {emma.id: true});
    open.close();
    await Future<void>.delayed(Duration.zero);

    expect(c.listen(provider, (_, _) {}).read().pending, isEmpty,
        reason: 'reopened, the sheet starts from what the server says');
  });

  test('a dismissed set question cancels the write, and the sheet is not left '
      'busy', () async {
    final (:controller, :states, container: _) = await start(
      film,
      index: const CollectionIndex([paddingtons]),
    );
    final host = _Host(keepTogether: null);

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(host.askedAbout, [boxSet.id], reason: 'the parent was asked');
    expect(posts(), isEmpty, reason: 'a dismissal is not "just this one"');
    expect(host.reports, 0);
    expect(states.any((s) => s.preparing), isTrue,
        reason: 'the index wait showed as work');
    expect(states.last.busy, isFalse);
    expect(states.last.notice, isNull);
  });

  test('a set whose membership cannot be read is a server error, and nothing '
      'is asked or written', () async {
    final (:controller, :states, container: _) = await start(
      boxSet,
      set: () => Future<CollectionSet>.error(StateError('offline')),
    );
    final host = _Host();

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(states.last.notice, const AssignNotice.serverError());
    expect(host.confirmed, 0);
    expect(posts(), isEmpty);
    expect(states.last.busy, isFalse);
  });

  test('a pre-flight failure counts what could not be read and leaves no '
      'fix-forward offer', () async {
    server.onQuery('/Users/admin-1/Items/film-2', (_) => true, status: 404);
    final (:controller, :states, container: _) = await start(
      boxSet,
      set: () async => paddingtons,
    );
    final host = _Host();

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(states.last.notice, const AssignNotice.preflightFailed(1));
    expect(states.last.unfinished, isNull);
    expect(posts(), isEmpty, reason: 'nothing is written past a pre-flight');
    expect(states.any((s) => s.applying), isTrue);
    expect(states.last.busy, isFalse);
  });

  test('a sheet closed while the warning was up writes nothing', () async {
    // A removal: it asks no set question, so the check after the warning is
    // the only thing between a closed sheet and the write.
    final (:controller, :states, container: _) = await start(film);
    controller.toggle(emma.id, false);
    final host = _Host(closeWhileAsked: true);

    await controller.apply(
      host,
      states.last.diffFrom([
        const AssignRow(
          child: emma,
          label: 'kids-emma',
          hasLabel: true,
          visibleCount: 3,
          libraryTotal: 10,
        ),
      ]),
      libraryTotal: 10,
    );

    expect(host.confirmed, 1);
    expect(posts(), isEmpty);
    expect(host.reports, 0);
  });

  // Ground rule 1's hard warning: the one thing between a tap and a child
  // losing the last thing they have. A "no" has to stop the write.
  test('a declined last-item warning writes nothing, for a film', () async {
    final (:controller, :states, container: _) = await start(film);
    final host = _Host(confirm: false);

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(host.confirmed, 1);
    expect(posts(), isEmpty);
    expect(host.reports, 0);
    expect(states.last.busy, isFalse);
  });

  test('a declined last-item warning writes nothing, for a set', () async {
    final (:controller, :states, container: _) = await start(
      boxSet,
      set: () async => paddingtons,
    );
    final host = _Host(confirm: false);

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(host.confirmed, 1);
    expect(posts(), isEmpty);
    expect(host.reports, 0);
    expect(states.last.busy, isFalse);
  });

  test('a set that is written in full is refreshed and reported once',
      () async {
    final (:controller, :states, :container) = await start(
      boxSet,
      set: () async => paddingtons,
    );
    final host = _Host();
    final revision = container.read(libraryRevisionProvider);

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(posts(), containsAll(<String>['/Items/film-1', '/Items/set-1']));
    expect(host.reports, 1);
    expect(host.touching, {boxSet.id, film.id, sequel.id});
    expect(states.last.unfinished, isNull);
    expect(container.read(libraryRevisionProvider), revision + 1,
        reason: 'the grid and its count are refetched after the write');
  });

  test('a single film is written, refreshed and reported', () async {
    final (:controller, :states, container: _) = await start(film);
    final host = _Host();

    await controller.apply(
      host,
      states.last.diffFrom([row]),
      libraryTotal: 10,
    );

    expect(posts(), contains('/Items/film-1'));
    expect(host.reports, 1);
    expect(host.touching, {film.id});
    expect(states.last.notice, isNull);
    expect(states.last.applying, isFalse);
  });
}

class _Host implements AssignSheetHost {
  _Host({
    this.confirm = true,
    this.keepTogether = false,
    this.closeWhileAsked = false,
  });

  /// The parent's answer to the last-item warning.
  final bool confirm;
  final bool? keepTogether;
  final bool closeWhileAsked;

  @override
  bool mounted = true;

  int confirmed = 0;
  int reports = 0;
  Set<String>? touching;
  final askedAbout = <String>[];

  @override
  Future<bool> confirmLastItem(
    TagDiff diff, {
    required Set<String> touching,
  }) async {
    confirmed++;
    if (closeWhileAsked) mounted = false;
    return confirm;
  }

  @override
  Future<bool?> askKeepSetTogether(CollectionSet set) async {
    askedAbout.add(set.collection.id);
    return keepTogether;
  }

  @override
  void reportAndClose({
    required TagDiff diff,
    required Future<Map<String, int>> counts,
    required int libraryTotal,
    required Future<void> Function() undo,
    required Set<String> touching,
  }) {
    reports++;
    this.touching = touching;
  }
}
