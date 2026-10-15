// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

import 'support/fake_jellyfin_server.dart';

/// Every per-session family is keyed on [AuthSession]. These pin that two
/// equal sessions are one key, and that a different token is another.
void main() {
  AuthSession session({String token = 'token-1'}) => AuthSession(
        serverUrl: 'http://host:8096',
        accessToken: token,
        userId: 'admin-1',
        userName: 'Parent',
      );

  ProviderContainer container() {
    const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');
    final c = ProviderContainer(
      overrides: [
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: FakeJellyfinServer()),
        ),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('two sessions with the same fields are equal, and hash alike', () {
    final a = session();
    final b = session();

    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('two equal sessions share one provider instance', () {
    // What identity equality got wrong: an equal session built anywhere else
    // forked the family into a second client.
    final c = container();

    expect(
      identical(
        c.read(libraryApiProvider(session())),
        c.read(libraryApiProvider(session())),
      ),
      isTrue,
    );
  });

  test('a request object wrapping equal sessions is one key too', () {
    final a = ChildLibrariesRequest(session: session(), childId: 'kid-1');
    final b = ChildLibrariesRequest(session: session(), childId: 'kid-1');

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('a new token is a new key, so no client built for the old one is reused',
      () {
    final c = container();

    expect(session(token: 'token-1'), isNot(session(token: 'token-2')));
    expect(
      identical(
        c.read(libraryApiProvider(session(token: 'token-1'))),
        c.read(libraryApiProvider(session(token: 'token-2'))),
      ),
      isFalse,
    );
  });

  test('the token stays out of toString', () {
    expect(session(token: 'secret-token').toString(),
        isNot(contains('secret-token')));
  });
}
