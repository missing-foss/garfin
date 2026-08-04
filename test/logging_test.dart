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

  test('strips the access token out of an authentication response', () {
    // The response to `POST /Users/AuthenticateByName`. That is a live *admin*
    // token — the same argument as the Quick Connect secret above, one field
    // over, and the reason `Secret` alone was not enough.
    expect(
      redactSecrets(
        '{"AccessToken":"988dc435d3b64611","ServerId":"2569","User":{}}',
      ),
      '{"AccessToken":"REDACTED","ServerId":"2569","User":{}}',
    );
    expect(
      redactSecrets('{"access_token":"988dc435"}'),
      '{"access_token":"REDACTED"}',
    );
  });

  test('strips the token out of the Authorization header', () {
    // The header the interceptor builds. Nothing logs it today, but it is the
    // one string in the app guaranteed to contain the token.
    expect(
      redactSecrets(
        'MediaBrowser Token="abc123", Client="Garfin", DeviceId="d1"',
      ),
      'MediaBrowser Token="REDACTED", Client="Garfin", DeviceId="d1"',
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

  test('matches whole names, not fragments of longer ones', () {
    // `myapikey` needs the lookbehind; `AccessTokenExpiry` needs the name to
    // run up against the separator. Between them they pin both halves of the
    // pattern — the failure they guard against is a half-redacted string, which
    // reads as though redaction ran and did nothing.
    expect(redactSecrets('myapikey=keepme'), 'myapikey=keepme');
    expect(
      redactSecrets('{"AccessTokenExpiry":"2026-08-04"}'),
      '{"AccessTokenExpiry":"2026-08-04"}',
    );
  });

  test('leaves ordinary text alone', () {
    const message = 'jellyfin call failed: /Users/Me (HTTP 401)';
    expect(redactSecrets(message), message);
  });
}
