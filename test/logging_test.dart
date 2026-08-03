// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/logging.dart';

/// The Quick Connect exchange puts the secret in a query string, so anything
/// that prints a request URI prints a live credential. This is the backstop for
/// that — the primary defence is `JellyfinException` never carrying the URI in
/// the first place.
void main() {
  test('strips a Quick Connect secret out of a URL', () {
    expect(
      redactSecrets(
        'DioException: GET http://host:8096/QuickConnect/Connect?secret=abc123',
      ),
      endsWith('/QuickConnect/Connect?secret=REDACTED'),
    );
  });

  test('strips a secret sitting in the middle of a query string', () {
    expect(
      redactSecrets('/Connect?secret=abc123&userId=7'),
      '/Connect?secret=REDACTED&userId=7',
    );
  });

  test('strips the other things Jellyfin accepts a credential as', () {
    expect(redactSecrets('?api_key=abc'), '?api_key=REDACTED');
    expect(redactSecrets('?ApiKey=abc'), '?ApiKey=REDACTED');
    expect(redactSecrets('Pw=hunter2'), 'Pw=REDACTED');
  });

  test('leaves ordinary text alone', () {
    const message = 'jellyfin call failed: /Users/Me (HTTP 401)';
    expect(redactSecrets(message), message);
  });
}
