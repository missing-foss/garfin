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

  test('strips the secret out of a response body, not just a query string', () {
    // The shape a leak would actually have: measured on 10.11.11, the response
    // to `GET /QuickConnect/Connect` carries the live secret as JSON. A pattern
    // that only knew about `secret=` would pass this through whole.
    expect(
      redactSecrets(
        '{"Authenticated":false,"Secret":"DA4C1F204EB7","Code":"793600"}',
      ),
      '{"Authenticated":false,"Secret":"REDACTED","Code":"793600"}',
    );
  });

  test('leaves a neighbouring field alone', () {
    // The six-digit code is not a credential — it is inert without the secret,
    // and it is meant to be read off a screen. Redacting it would make a log
    // useless for diagnosing a pairing without making anything safer.
    expect(
      redactSecrets('{"Code":"793600"}'),
      '{"Code":"793600"}',
    );
  });

  test('leaves ordinary text alone', () {
    const message = 'jellyfin call failed: /Users/Me (HTTP 401)';
    expect(redactSecrets(message), message);
  });
}
