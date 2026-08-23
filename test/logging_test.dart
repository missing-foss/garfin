// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/logging.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';

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

  test('the on-screen diagnostic names the errno, and is scrubbed', () {
    // The reason this exists: "Garfin couldn't reach your server" is the same
    // sentence for four different problems, and the errno is what tells them
    // apart — 13 is the platform refusing the socket, 111 is nothing
    // listening, 113 is the wrong network.
    final described = JellyfinException.describeCause(
      DioException(
        requestOptions: RequestOptions(path: '/QuickConnect/Enabled'),
        type: DioExceptionType.connectionError,
        error: const SocketException(
          'Connection failed',
          osError: OSError('Permission denied', 13),
        ),
      ),
    );

    expect(described, startsWith('connectionError · SocketException'));
    expect(described, contains('errno = 13'));
  });

  test('the diagnostic never puts server text on the screen', () {
    // `DioException.error` is an arbitrary object. When a response body fails
    // to parse it is a `FormatException`, whose `toString()` embeds up to 75
    // characters of that body — measured, a proxy's HTML error page complete
    // with an internal hostname. The class promises not to show server text,
    // so only socket-level causes contribute their message.
    const page = '<html><body><h1>502 Bad Gateway</h1>'
        '<p>nginx: upstream jellyfin.internal refused</p></body></html>';
    late final FormatException parseFailure;
    try {
      jsonDecode(page);
      fail('expected the page not to parse as JSON');
    } on FormatException catch (e) {
      parseFailure = e;
    }

    final described = JellyfinException.describeCause(
      DioException(
        requestOptions: RequestOptions(path: '/Users/AuthenticateByName'),
        type: DioExceptionType.unknown,
        error: parseFailure,
      ),
    );

    expect(described, 'unknown · FormatException');
    expect(described, isNot(contains('502')));
    expect(described, isNot(contains('jellyfin.internal')));
    expect(described, isNot(contains('<html>')));
  });

  test('but socket-level causes still carry their errno', () {
    // The whitelist must not throw away the thing the field exists for.
    final described = JellyfinException.describeCause(
      DioException(
        requestOptions: RequestOptions(path: '/QuickConnect/Enabled'),
        type: DioExceptionType.connectionError,
        error: const SocketException(
          'Connection failed',
          osError: OSError('No route to host', 113),
        ),
      ),
    );

    expect(described, contains('errno = 113'));
  });

  test('the diagnostic cannot carry a credential onto the screen', () {
    // Belt and braces: the whitelist above is what keeps server text out, and
    // this is what keeps a credential out of the text that *is* allowed
    // through. A `SocketException` carries the address it failed on, so the
    // allowed path is not automatically a safe one.
    final described = JellyfinException.describeCause(
      DioException(
        requestOptions: RequestOptions(path: '/QuickConnect/Connect'),
        type: DioExceptionType.connectionError,
        error: const SocketException(
          'Connection failed on /QuickConnect/Connect?secret=DA4C1F204EB7',
        ),
      ),
    );

    expect(described, contains('secret=REDACTED'));
    expect(described, isNot(contains('DA4C1F204EB7')));
  });

  test('leaves ordinary text alone', () {
    const message = 'jellyfin call failed: /Users/Me (HTTP 401)';
    expect(redactSecrets(message), message);
  });
}
