// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/country_lookup.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

import 'support/fake_jellyfin_server.dart';

/// Country names to ISO codes, for the item sheet's flags (#166).
///
/// The rows are in the shape 12.1.0's `/Localization/Countries` answers,
/// measured 2026-09-19: `Name` is the code, `DisplayName` the English name.
void main() {
  Map<String, dynamic> row(String code, String three, String name) => {
    'Name': code,
    'DisplayName': name,
    'TwoLetterISORegionName': code,
    'ThreeLetterISORegionName': three,
  };

  final lookup = CountryLookup.fromRows([
    row('FR', 'FRA', 'France'),
    row('US', 'USA', 'United States'),
    row('GB', 'GBR', 'United Kingdom'),
  ]);

  group('codeFor', () {
    test('finds a display name, whatever its case', () {
      expect(lookup.codeFor('France'), 'FR');
      expect(lookup.codeFor('united kingdom'), 'GB');
      expect(lookup.codeFor('  France  '), 'FR');
    });

    test('finds a two- or three-letter code', () {
      expect(lookup.codeFor('FR'), 'FR');
      expect(lookup.codeFor('USA'), 'US',
          reason: 'a provider writing USA needs no alias');
    });

    test("finds TMDB's United States of America through the alias", () {
      // Measured on 12.1.0 with TMDB: the server's own name is United States.
      expect(lookup.codeFor('United States of America'), 'US');
    });

    test('an alias never answers a code the server does not have', () {
      final noUs = CountryLookup.fromRows([row('FR', 'FRA', 'France')]);

      expect(noUs.codeFor('United States of America'), isNull);
    });

    test('a name nobody knows is null, not a guess', () {
      expect(lookup.codeFor('Soviet Union'), isNull);
      expect(lookup.codeFor(''), isNull);
    });

    test('an empty lookup knows nothing', () {
      expect(const CountryLookup.empty().codeFor('France'), isNull);
      expect(const CountryLookup.empty().codes, isEmpty);
    });
  });

  test('codes are the two-letter codes of every usable row', () {
    final withJunk = CountryLookup.fromRows([
      row('FR', 'FRA', 'France'),
      {'DisplayName': 'No code at all'},
      {'TwoLetterISORegionName': 'XYZ', 'DisplayName': 'Three letters'},
    ]);

    expect(withJunk.codes, {'FR'});
    expect(withJunk.codeFor('No code at all'), isNull);
  });

  group('flagEmoji', () {
    test('is the pair of regional indicator symbols', () {
      expect(CountryLookup.flagEmoji('FR'), '\u{1F1EB}\u{1F1F7}');
      expect(CountryLookup.flagEmoji('us'), '\u{1F1FA}\u{1F1F8}');
    });

    test('is null for anything that is not two letters', () {
      for (final bad in ['', 'F', 'FRA', 'F1', '--', 'É']) {
        expect(CountryLookup.flagEmoji(bad), isNull, reason: bad);
      }
    });
  });

  group('through the API', () {
    JellyfinApi apiWith(FakeJellyfinServer server) => JellyfinApiFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    ).create(baseUrl: 'http://host:8096', readToken: () => 'token');

    test('countries() reads the server list into a lookup', () async {
      final server = FakeJellyfinServer()
        ..on('/Localization/Countries', json: [
          row('FR', 'FRA', 'France'),
          row('US', 'USA', 'United States'),
        ]);

      final countries = await apiWith(server).countries();

      expect(countries.codes, {'FR', 'US'});
      expect(countries.codeFor('France'), 'FR');
      expect(countries.codeFor('United States of America'), 'US');
    });

    test('a reply that is not a list is an error, not an empty lookup', () {
      // The provider turns an error into an empty lookup on purpose; the API
      // must not decide that for it by answering empty itself.
      final server = FakeJellyfinServer()
        ..on('/Localization/Countries', json: {'unexpected': true});

      expect(apiWith(server).countries(), throwsA(isA<Object>()));
    });
  });
}
