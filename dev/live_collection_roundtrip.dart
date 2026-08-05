// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

// The standing review gate for the write path, for collections.
//
// `docs/JELLYFIN-API.md`: "Every PR that touches the write path must
// demonstrate a round-trip against a live server: stand up Jellyfin in Docker,
// snapshot the item's full JSON, write one tag through the code under review,
// and diff. Prove it, don't assert it."
//
// This drives the **real** repository — `AssignRepository.applyToCollection`,
// through the real `JellyfinApi` and dio — against a server you point it at,
// and prints the diff for the container and every member.
//
// It lives in `dev/` rather than `test/` on purpose: `flutter test` runs
// `test/` and this needs a server, so keeping it out of that directory means it
// can never become a silently-skipped check that still reports green.
//
//     # Follow the protocol in docs/JELLYFIN-API.md: prove the port is free,
//     # bind 127.0.0.1 only, and assert StartupWizardCompleted is false FIRST.
//     GARFIN_SERVER=http://127.0.0.1:18099 \
//     GARFIN_TOKEN=… GARFIN_ADMIN_ID=… GARFIN_COLLECTION_ID=… \
//     GARFIN_CHILD_ID=… GARFIN_LABEL=kids-emma \
//     ~/sdk/flutter/bin/flutter test dev/live_collection_roundtrip.dart
//
// A developer machine may already be running a real Jellyfin on the default
// port. This writes tags. Point it at a throwaway.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/assign_repository.dart';
import 'package:garfin/repositories/collection_repository.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

void main() {
  final env = Platform.environment;
  final server = env['GARFIN_SERVER'];
  final token = env['GARFIN_TOKEN'];
  final adminId = env['GARFIN_ADMIN_ID'];
  final collectionId = env['GARFIN_COLLECTION_ID'];
  final label = env['GARFIN_LABEL'] ?? 'kids-probe';
  // The count re-fetched after a write (ground rule 1) is asked *as the child*,
  // so this has to be a user the server knows: an invented id answers 400.
  final childId = env['GARFIN_CHILD_ID'];

  test('a collection write, round-tripped against a live server', () async {
    if (server == null ||
        token == null ||
        adminId == null ||
        collectionId == null ||
        childId == null) {
      fail('set GARFIN_SERVER, GARFIN_TOKEN, GARFIN_ADMIN_ID, '
          'GARFIN_COLLECTION_ID and GARFIN_CHILD_ID — see the header of '
          'this file');
    }

    final api = JellyfinApiFactory(
      identity: const DeviceIdentity(
        deviceId: 'roundtrip-probe',
        deviceName: 'Garfin round-trip',
      ),
    ).create(baseUrl: server, readToken: () => token);

    final collections = CollectionRepository(api: api, adminUserId: adminId);
    final assign = AssignRepository(api: api, adminUserId: adminId);

    final index = await collections.index();
    final set = index.byId(collectionId);
    if (set == null) fail('no collection $collectionId on that server');

    final child = JellyfinUser(
      id: childId,
      name: 'Probe',
      policy: UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: [label],
      ),
    );
    final give = TagDiff([
      TagChange(child: child, label: label, adding: true),
    ]);

    final ids = <String>[collectionId, ...set.memberIds];

    Future<Map<String, Map<String, dynamic>>> snapshot() async {
      final out = <String, Map<String, dynamic>>{};
      for (final id in ids) {
        out[id] = await api.fullItem(userId: adminId, itemId: id);
      }
      return out;
    }

    void report(
      String what,
      Map<String, Map<String, dynamic>> before,
      Map<String, Map<String, dynamic>> after,
    ) {
      stdout.writeln('\n=== $what ===');
      for (final id in ids) {
        final b = before[id]!;
        final a = after[id]!;
        final lost = b.keys.toSet().difference(a.keys.toSet());
        final gained = a.keys.toSet().difference(b.keys.toSet());
        final changed = b.keys
            .where((k) => a.containsKey(k) && '${b[k]}' != '${a[k]}')
            .toList();
        stdout.writeln('${b['Type']} "${b['Name']}"');
        stdout.writeln('  fields ${b.length} -> ${a.length}   '
            'LOST $lost  GAINED $gained  CHANGED $changed');
        stdout.writeln('  Tags ${b['Tags']} -> ${a['Tags']}');
        // Ground rule 2: the change is the tag and the server's own Etag.
        // Anything else in CHANGED is a field this write corrupted.
        expect(lost, isEmpty);
        expect(gained, isEmpty);
        expect(changed.toSet().difference({'Tags', 'Etag'}), isEmpty);
      }
    }

    stdout.writeln('collection "${set.collection.name}", '
        '${set.size} members, label "$label"');

    final before = await snapshot();
    final outcome = await assign.applyToCollection(
      collectionId: collectionId,
      memberIds: set.memberIds,
      diff: give,
    );
    final afterWrite = await snapshot();
    report('after applyToCollection', before, afterWrite);
    stdout.writeln('outcome: ${outcome.written.length} written, '
        '${outcome.failed.length} failed, setMarked=${outcome.setMarked}');

    expect(outcome.isComplete, isTrue);
    for (final id in ids) {
      expect(
        (afterWrite[id]!['Tags'] as List).map((t) => '$t'.toLowerCase()),
        contains(label.toLowerCase()),
        reason: 'the label must be on the container as well as every member',
      );
    }

    // The pre-flight, against the real server: one id that does not exist and
    // the whole batch is abandoned with nothing written.
    var refused = false;
    try {
      await assign.applyToCollection(
        collectionId: collectionId,
        memberIds: [...set.memberIds, 'deadbeefdeadbeefdeadbeefdeadbeef'],
        diff: AssignRepository.reverse(give),
      );
    } on CollectionPreflightException catch (error) {
      refused = true;
      stdout.writeln('\npre-flight refused the batch: '
          '${error.unreadable.length} unreadable');
    }
    expect(refused, isTrue);
    final afterRefusal = await snapshot();
    for (final id in ids) {
      expect(afterRefusal[id]!['Tags'], afterWrite[id]!['Tags'],
          reason: 'an abandoned batch must not have written anything');
    }
    stdout.writeln('nothing changed: the label is still on all '
        '${ids.length} items');

    // And back off again, as the forward write Undo actually is.
    await assign.undoCollection(
      collectionId: collectionId,
      memberIds: set.memberIds,
      diff: give,
    );
    final afterUndo = await snapshot();
    report('after undoCollection', afterWrite, afterUndo);
    for (final id in ids) {
      expect(
        (afterUndo[id]!['Tags'] as List).map((t) => '$t'.toLowerCase()),
        isNot(contains(label.toLowerCase())),
      );
    }
    stdout.writeln('\nthe library is back where it started');
  });
}
