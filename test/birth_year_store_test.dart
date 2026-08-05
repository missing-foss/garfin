// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one thing Garfin stores about a child that Jellyfin does not hold.
///
/// Asserted against the real `shared_preferences` rather than a fake, because
/// the claims worth making here are about what ends up on disk — `SECURITY.md`
/// enumerates every key, and this is the newest one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late BirthYearStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    store = BirthYearStore(prefs);
  });

  test('a year round-trips, keyed by user id', () async {
    await store.write('user-1', 2015);

    expect(store.read('user-1'), 2015);
    // By id, not by name: renaming a child in Jellyfin must not reattach one
    // child's age to another's card.
    expect(prefs.getKeys(), contains('birth_year_user-1'));
  });

  test('users do not share a year', () async {
    await store.write('user-1', 2015);
    await store.write('user-2', 2011);

    expect(store.read('user-1'), 2015);
    expect(store.read('user-2'), 2011);
  });

  test('an unset user reads as null rather than a default', () {
    // A default here would put a fabricated age beside a child's name.
    expect(store.read('nobody'), isNull);
  });

  test('null clears the key rather than storing a sentinel', () async {
    await store.write('user-1', 2015);
    await store.write('user-1', null);

    expect(store.read('user-1'), isNull);
    expect(prefs.getKeys(), isNot(contains('birth_year_user-1')));
  });

  test('an implausible year is refused, not stored', () async {
    await store.write('user-1', 12);
    await store.write('user-2', 99999);

    expect(store.read('user-1'), isNull);
    expect(store.read('user-2'), isNull);
    expect(prefs.getKeys(), isEmpty);
  });

  test('a value already on disk gets the same bounds check', () async {
    // Bounds can change. A number that arrived earlier is not more trustworthy
    // for having done so, and an age of several hundred years has no sensible
    // layout on the card.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'birth_year_user-1': 3,
    });
    prefs = await SharedPreferences.getInstance();
    store = BirthYearStore(prefs);

    expect(store.read('user-1'), isNull);
  });

  test('clearAll forgets every year and nothing else', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'birth_year_user-1': 2015,
      'birth_year_user-2': 2011,
      'server_url': 'http://host:8096',
      'unlock_required': true,
    });
    prefs = await SharedPreferences.getInstance();
    store = BirthYearStore(prefs);

    await store.clearAll();

    // Ids are per-server, so carrying them across a sign-out would at best be
    // dead keys and at worst attach one household's ages to another's accounts.
    expect(store.read('user-1'), isNull);
    expect(store.read('user-2'), isNull);
    // Sign-out is not this store's business beyond its own keys.
    expect(prefs.getString('server_url'), 'http://host:8096');
    expect(prefs.getBool('unlock_required'), true);
  });
}
