// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/media_browser_auth.dart';

import 'support/fake_jellyfin_server.dart';

/// The `Authorization` header is the one thing every later request depends on,
/// so these tests are about its *shape*, not about any one endpoint.
void main() {
  const identity = DeviceIdentity(
    deviceId: 'device-1',
    deviceName: 'Android 14 (API 34)',
    client: 'Garfin',
    version: '0.1.0',
  );

  group('header value', () {
    test('carries every field, token first, when signed in', () {
      final header = MediaBrowserAuthInterceptor.buildHeader(
        identity: identity,
        token: 'token-abc',
      );

      expect(
        header,
        'MediaBrowser Token="token-abc", Client="Garfin", '
        'Device="Android 14 (API 34)", DeviceId="device-1", Version="0.1.0"',
      );
    });

    test('omits Token entirely when signed out', () {
      final header =
          MediaBrowserAuthInterceptor.buildHeader(identity: identity);

      // Not `Token=""`. Some Jellyfin versions read an empty token as a failed
      // authentication and answer 401 to calls meant to be anonymous — which
      // would break the Quick Connect exchange, all of which is anonymous.
      expect(header, isNot(contains('Token=')));
      expect(header, contains('Client="Garfin"'));
      expect(header, contains('DeviceId="device-1"'));
    });

    test('strips quotes and newlines out of the device name', () {
      // The device name is the one field that comes from the platform rather
      // than from Garfin. A stray quote would end the parameter early; a
      // newline would let the rest be read as a separate header.
      const hostile = DeviceIdentity(
        deviceId: 'device-1',
        deviceName: 'Pixel" , Injected="yes\r\nX-Evil: 1',
      );

      final header =
          MediaBrowserAuthInterceptor.buildHeader(identity: hostile);

      // The hostile text survives as *text* — that is fine and deliberate. What
      // must not survive is its structure: no line break to start a second
      // header with, and no quote to close the parameter early with. Both are
      // gone, so the whole thing stays one `Device` value.
      expect(header.contains('\n'), isFalse);
      expect(header.contains('\r'), isFalse);
      expect(header, contains('Device="Pixel , Injected=yesX-Evil: 1"'));
      expect(
        RegExp('"').allMatches(header).length,
        8,
        reason: 'four parameters, two quotes each — nothing extra crept in',
      );
    });
  });

  group('interceptor', () {
    test('attaches the header exactly once, on every request', () async {
      final server = FakeJellyfinServer()
        ..fallback(json: true);
      final api = JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: 'http://host:8096', readToken: () => 'token-abc');

      await api.quickConnectEnabled();
      await api.quickConnectEnabled();

      expect(server.requests, hasLength(2));
      for (final request in server.requests) {
        final value = request.headers[MediaBrowserAuthInterceptor.headerName];
        // A List here would mean two headers were attached and dio joined
        // them — Jellyfin would then parse the pair as one malformed value.
        expect(value, isA<String>());
        expect(
          RegExp('Token=').allMatches(value as String).length,
          1,
          reason: 'the token must appear once, not once per interceptor pass',
        );
      }
    });

    test('replaces an Authorization header a caller already set', () {
      final interceptor = MediaBrowserAuthInterceptor(
        identity: identity,
        readToken: () => 'token-fresh',
      );
      // A retry that reuses its RequestOptions, or a caller setting one by
      // hand. Either way exactly one header must go out, and it must be the
      // current one — a stale token appended alongside a fresh one is the
      // failure this guards.
      final options = RequestOptions(
        path: '/Users/Me',
        headers: <String, dynamic>{
          MediaBrowserAuthInterceptor.headerName:
              'MediaBrowser Token="token-stale"',
        },
      );

      interceptor.onRequest(options, RequestInterceptorHandler());

      final value = options.headers[MediaBrowserAuthInterceptor.headerName];
      expect(value, isA<String>());
      expect(value as String, contains('token-fresh'));
      expect(value, isNot(contains('token-stale')));
    });

    test('picks up a sign-in without the client being rebuilt', () async {
      String? token;
      final server = FakeJellyfinServer()..fallback(json: true);
      final api = JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: 'http://host:8096', readToken: () => token);

      await api.quickConnectEnabled();
      token = 'token-later';
      await api.quickConnectEnabled();

      final headerName = MediaBrowserAuthInterceptor.headerName;
      expect(server.requests.first.headers[headerName], isNot(contains('Token=')));
      expect(
        server.requests.last.headers[headerName],
        contains('Token="token-later"'),
      );
    });
  });
}
