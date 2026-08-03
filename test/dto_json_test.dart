// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/authentication_result.dart';
import 'package:garfin/models/dto_json.dart';
import 'package:garfin/models/quick_connect.dart';

/// Jellyfin 10.11.11 answered `/System/Info/Public` in **camelCase with HTTP
/// 200** for about a second after a restart, before settling on the PascalCase
/// its `Accept: application/json` contract promises. A parser keyed on exact
/// names reads that as an object with every field missing — which for a sign-in
/// is an empty access token and a policy that looks like "not an administrator".
///
/// So the DTOs read field names case-insensitively, and these are the tests
/// that keep that true.
void main() {
  group('readField', () {
    test('prefers the exact name', () {
      expect(readField({'Name': 'a', 'name': 'b'}, 'Name'), 'a');
    });

    test('falls back to a differently cased name', () {
      expect(readString({'accessToken': 'abc'}, 'AccessToken'), 'abc');
      expect(readBool({'isAdministrator': true}, 'IsAdministrator'), isTrue);
      expect(readMap({'policy': <String, dynamic>{}}, 'Policy'), isNotNull);
    });

    test('a missing name is null, and a missing flag is false', () {
      expect(readString(<String, dynamic>{}, 'Name'), isNull);
      // The safe direction: absent must never read as "administrator".
      expect(readBool(<String, dynamic>{}, 'IsAdministrator'), isFalse);
    });

    test('a wrongly typed value is treated as absent', () {
      expect(readString({'Name': 42}, 'Name'), isNull);
      expect(readMap({'Policy': 'not an object'}, 'Policy'), isNull);
    });
  });

  group('DTOs survive a camelCase reply', () {
    test('AuthenticationResult keeps its token and its admin flag', () {
      final result = AuthenticationResult.fromJson({
        'accessToken': 'token-abc',
        'serverId': 'server-1',
        'user': {
          'id': 'user-1',
          'name': 'Alex',
          'policy': {'isAdministrator': true, 'isDisabled': false},
        },
      });

      expect(result.accessToken, 'token-abc');
      expect(result.user.name, 'Alex');
      // The one that matters: read case-sensitively this would be false, and
      // an administrator would be refused at sign-in for no reason.
      expect(result.user.policy.isAdministrator, isTrue);
    });

    test('QuickConnect keeps its code and its approval flag', () {
      final initiation = QuickConnectInitiation.fromJson(
        {'code': '123456', 'secret': 'shhh'},
      );
      expect(initiation.code, '123456');
      expect(initiation.secret, 'shhh');
      expect(
        QuickConnectStatus.fromJson({'authenticated': true}).authenticated,
        isTrue,
      );
    });
  });

  test('the token stays out of toString', () {
    final result = AuthenticationResult.fromJson({
      'AccessToken': 'token-abc',
      'User': {'Name': 'Alex', 'Policy': <String, dynamic>{}},
    });

    // These objects end up in Riverpod state, and Riverpod's observers print
    // state transitions.
    expect(result.toString(), isNot(contains('token-abc')));
    expect(
      const QuickConnectInitiation(code: '123456', secret: 'shhh').toString(),
      isNot(contains('shhh')),
    );
  });
}
