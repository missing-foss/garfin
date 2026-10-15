// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/widgets/error_notice.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// A 30x is reported with the address it names, and never followed.
///
/// **Measured with Garfin's own client, against two local listeners:** a
/// redirect to another origin — another port, as `http://` to `https://` is —
/// arrived **without** the `Authorization` header, and one within the same
/// origin re-sent it. So following a proxy's `http` to `https` redirect turned
/// every call into a 401, and the session check a 401 starts would sign the
/// parent out as "unauthorized" over an address change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverUrl = 'http://host:8096';
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  late FakeJellyfinServer server;
  late JellyfinApi api;

  setUp(() {
    server = FakeJellyfinServer();
    api = JellyfinApiFactory(identity: identity, adapter: server)
        .create(baseUrl: serverUrl, readToken: () => 'token');
  });

  void movesTo(String? location, {String path = '/Users/Me'}) =>
      server.onQuery(
        path,
        (_) => true,
        status: 301,
        headers: {
          if (location != null) 'location': [location],
        },
      );

  Future<JellyfinException> failure() async {
    try {
      await api.currentUser();
    } on JellyfinException catch (error) {
      return error;
    }
    fail('the call should have failed');
  }

  test('the client does not follow redirects', () async {
    movesTo('https://host/Users/Me');
    await failure();

    expect(server.requests.single.followRedirects, isFalse);
  });

  test('a 301 is "moved", with the address to sign in with', () async {
    movesTo('https://host:8920/Users/Me');

    final error = await failure();

    expect(error.kind, JellyfinErrorKind.moved);
    expect(error.detail, 'https://host:8920',
        reason: 'the request path comes back off: this is what a parent types');
  });

  test('a relative Location is resolved against the server', () async {
    movesTo('/jf/Users/Me');

    expect((await failure()).detail, 'http://host:8096/jf');
  });

  test('no query reaches the screen', () async {
    // A Quick Connect poll carries its secret in the query.
    movesTo('https://host/Users/Me?secret=abc123');

    final detail = (await failure()).detail!;
    expect(detail, 'https://host');
    expect(detail, isNot(contains('abc123')));
  });

  test('no Location: moved, with no address', () async {
    movesTo(null);

    final error = await failure();
    expect(error.kind, JellyfinErrorKind.moved);
    expect(error.detail, isNull);
  });

  test('the sentence names the address, or says there is none', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(
      jellyfinErrorText(
        l10n,
        const JellyfinException(
          JellyfinErrorKind.moved,
          detail: 'https://host',
        ),
      ),
      contains('https://host'),
    );
    expect(
      jellyfinErrorText(
        l10n,
        const JellyfinException(JellyfinErrorKind.moved),
      ),
      l10n.errorMovedNoAddress,
    );
  });

  test('a stored session whose server moved stays signed in, and says so',
      () async {
    FlutterSecureStorage.setMockInitialValues(
      <String, String>{'jellyfin_access_token': 'token-abc'},
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': serverUrl,
      'user_id': 'admin-1',
      'user_name': 'Alex',
    });
    final prefs = await SharedPreferences.getInstance();
    movesTo('https://host/Users/Me');
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWith(
          (ref) => JellyfinApiFactory(
            identity: identity,
            adapter: server,
            signals: ref.watch(sessionSignalsProvider),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    await c.read(authControllerProvider.future);
    await pumpEventQueue();

    final state = c.read(authControllerProvider).value;
    expect(state, isA<AuthSignedIn>(),
        reason: 'an address change is not a refusal of the session');
    expect((state! as AuthSignedIn).offlineReason?.kind,
        JellyfinErrorKind.moved);
  });
}
