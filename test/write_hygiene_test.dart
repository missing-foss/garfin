// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/assign_repository.dart';
import 'package:garfin/repositories/auth_repository.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/repositories/server_settings_store.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Two orderings on the write path that held only by luck.
///
/// **Sign-in wrote the token first**, then the address and the account; an
/// interruption between them left a token that restored with an empty user
/// id, and every request went to `/Users//Items/…`. **And a tag write read
/// `Tags` in any casing but set `Tags`**, so a camelCase body would have been
/// posted with both keys.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverUrl = 'http://host:8096';
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  late FakeJellyfinServer server;
  late SharedPreferences prefs;

  setUp(() async {
    server = FakeJellyfinServer();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  AuthRepository auth(TokenStore tokens) => AuthRepository(
        apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
        tokenStore: tokens,
        settings: ServerSettingsStore(prefs),
        birthYears: BirthYearStore(prefs),
      );

  group('sign-in', () {
    test('stores the account before the token', () async {
      server.on('/Users/AuthenticateByName', json: authResultJson());
      final tokens = _Witness(prefs);

      await auth(tokens).signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'pw',
      );

      expect(tokens.userIdWhenWritten, isNotNull,
          reason: 'the token went in after the account it belongs to');
      expect(tokens.serverWhenWritten, serverUrl);
    });

    test('a token with no account id is not restored', () async {
      // What an interrupted sign-in used to leave: the token and the address,
      // and no account.
      await prefs.setString('server_url', serverUrl);
      const tokens = SecureTokenStore(FlutterSecureStorage());
      await tokens.write('token-abc');

      expect(await auth(tokens).restore(), isNull);
    });

    test('a token with an empty account id is not restored', () async {
      await prefs.setString('server_url', serverUrl);
      await prefs.setString('user_id', '');
      const tokens = SecureTokenStore(FlutterSecureStorage());
      await tokens.write('token-abc');

      expect(await auth(tokens).restore(), isNull);
    });
  });

  group('a tag write', () {
    final emma = JellyfinUser(
      id: 'kid-1',
      name: 'Emma',
      policy: const UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: ['kids-emma'],
      ),
    );
    final give = TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]);

    AssignRepository repository() => AssignRepository(
          api: JellyfinApiFactory(identity: identity, adapter: server)
              .create(baseUrl: serverUrl, readToken: () => 'token'),
          adminUserId: 'admin-1',
        );

    int posts() => server.requests.where((r) => r.method == 'POST').length;

    for (final (name, body) in [
      (
        'a camelCase body',
        <String, dynamic>{'id': 'item-1', 'name': 'Paddington', 'tags': <String>[]},
      ),
      (
        'a body with no exact Id key',
        <String, dynamic>{'id': 'item-1', 'Name': 'Paddington', 'Tags': <String>[]},
      ),
      // Refused twice over: `fullItem` rejects an answer about another item,
      // and the write path checks the exact key again. Removing either check
      // alone leaves this passing; it fails only when both are gone.
      (
        'a body whose Id is another item',
        <String, dynamic>{'Id': 'item-2', 'Name': 'Paddington', 'Tags': <String>[]},
      ),
      (
        'a body carrying both Tags and tags',
        <String, dynamic>{
          'Id': 'item-1',
          'Name': 'Paddington',
          'Tags': <String>[],
          'tags': <String>[],
        },
      ),
    ]) {
      test('$name is refused before anything is posted', () async {
        server
          ..on('/Users/admin-1/Items/item-1', json: body)
          ..fallback(json: <String, dynamic>{'TotalRecordCount': 1});

        await expectLater(
          repository().apply(itemId: 'item-1', diff: give),
          throwsA(isA<JellyfinException>()),
        );
        expect(posts(), 0);
      });
    }

    test('the PascalCase body it always gets is written', () async {
      server
        ..on('/Users/admin-1/Items/item-1', json: <String, dynamic>{
          'Id': 'item-1',
          'Name': 'Paddington',
          'Tags': <String>[],
        })
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 1});

      await repository().apply(itemId: 'item-1', diff: give);

      expect(posts(), 1, reason: 'the guard must not refuse the normal case');
    });
  });
}

/// A token store that notes what the preferences held when the token arrived.
class _Witness implements TokenStore {
  _Witness(this._prefs);

  final SharedPreferences _prefs;
  String? _token;
  String? userIdWhenWritten;
  String? serverWhenWritten;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async {
    userIdWhenWritten = _prefs.getString('user_id');
    serverWhenWritten = _prefs.getString('server_url');
    _token = token;
  }

  @override
  Future<void> clear() async => _token = null;
}
