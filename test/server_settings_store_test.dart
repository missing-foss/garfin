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
