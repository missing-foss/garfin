// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/server_settings_store.dart';

/// Whatever a parent types has to become a base URL dio can join paths onto.
/// Getting this wrong shows up as "Garfin can't reach your server" against an
/// address that is perfectly fine.
void main() {
  test('assumes http when no scheme is given', () {
    // A home Jellyfin on the LAN is usually plain HTTP, and guessing https
    // there fails with a TLS error that reads like the server is down. The
    // sign-in screen writes the resolved address back into the field, so the
    // guess is visible rather than silent.
    expect(normalizeServerUrl('jellyfin.local:8096'),
        'http://jellyfin.local:8096');
  });

  test('keeps an explicit scheme', () {
    expect(normalizeServerUrl('https://jellyfin.example.org'),
        'https://jellyfin.example.org');
  });

  test('strips trailing slashes', () {
    // dio joins baseUrl and a leading-slash path verbatim, so a trailing slash
    // would produce `http://host:8096//Users/Me`.
    expect(normalizeServerUrl('http://host:8096/'), 'http://host:8096');
    expect(normalizeServerUrl('http://host:8096///'), 'http://host:8096');
  });

  test('keeps a sub-path, which reverse proxies need', () {
    expect(normalizeServerUrl('http://host/jellyfin/'), 'http://host/jellyfin');
  });

  test('drops a query and a fragment', () {
    // Neither is ever part of a Jellyfin base URL, and carrying one would
    // append it to every request path.
    expect(normalizeServerUrl('http://host:8096/?a=1#x'), 'http://host:8096');
  });

  group('credentials in the address', () {
    test('are dropped, never carried into the stored URL', () {
      // They would otherwise be persisted to `shared_preferences` in clear,
      // written back into a visible text field, and interpolated into on-screen
      // error text. The access token is handled carefully everywhere else; this
      // was the one path that wasn't.
      expect(
        normalizeServerUrl('https://parent:hunter2@jf.example.org'),
        'https://jf.example.org',
      );
      expect(
        normalizeServerUrl('http://parent@host:8096/jellyfin/'),
        'http://host:8096/jellyfin',
      );
      expect(
        normalizeServerUrl('https://parent:hunter2@jf.example.org'),
        isNot(contains('hunter2')),
      );
    });

    test('are reported, so the loss is not silent', () {
      // Garfin cannot sign in through a proxy that does basic auth — Jellyfin
      // needs the `Authorization` header for itself and 10.11.11 removed every
      // alternative. Saying so beats a parent wondering why their working
      // address stopped working.
      expect(
        addressCarriesCredentials('https://parent:hunter2@jf.example.org'),
        isTrue,
      );
      expect(addressCarriesCredentials('parent@host:8096'), isTrue);
      expect(addressCarriesCredentials('http://host:8096'), isFalse);
      expect(addressCarriesCredentials(''), isFalse);
    });
  });

  test('trims surrounding whitespace', () {
    expect(normalizeServerUrl('  http://host:8096  '), 'http://host:8096');
  });

  test('refuses what is not a usable address', () {
    expect(normalizeServerUrl(''), isNull);
    expect(normalizeServerUrl('   '), isNull);
    expect(normalizeServerUrl('http://'), isNull);
    // A scheme Garfin cannot speak. Better refused on the address step than
    // turned into a request that fails for a reason nobody can read.
    expect(normalizeServerUrl('ftp://host'), isNull);
  });
}
