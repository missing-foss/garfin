// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/app_info.dart';
import 'package:garfin/repositories/update_repository.dart';

import 'support/fake_jellyfin_server.dart';

/// The update check (#66) — the one request Garfin makes to anything other than
/// the user's own server.
///
/// Two kinds of assertion here, and the first kind matters more. *What it
/// says* — up to date, available, rate-limited — is ordinary UI correctness.
/// *What it sends* is a privacy claim `SECURITY.md` makes in prose, on a call
/// to a third party, from an app holding a Jellyfin admin token.
void main() {
  late FakeJellyfinServer github;

  UpdateRepository build() {
    github = FakeJellyfinServer();
    return UpdateRepository(dio: Dio()..httpClientAdapter = github);
  }

  Map<String, Object?> release(String tag) => <String, Object?>{
        'tag_name': tag,
        'html_url': 'https://github.com/missing-foss/garfin/releases/tag/$tag',
        'draft': false,
        'prerelease': true,
      };

  group('what leaves the phone', () {
    test('carries no Authorization header, and no token anywhere', () async {
      // **The failure this exists for.** Garfin's Jellyfin `Dio` attaches
      // `Authorization: MediaBrowser … Token="…"` — an admin token for the
      // user's server — to everything it sends. Reusing that client here would
      // post it to api.github.com on a button press, silently and successfully.
      // `update_providers.dart` builds a separate client with no interceptors;
      // this is what says so out loud.
      final repo = build();
      github.on(UpdateRepository.releasesUrl, json: <dynamic>[]);

      await repo.check();

      final sent = github.requests.single;
      expect(sent.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      expect(sent.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-emby-token')));
      // Not just the header: nothing anywhere in the request may look like a
      // credential or name the household's server.
      final everything =
          '${sent.uri}${sent.headers}${sent.data ?? ''}'.toLowerCase();
      expect(everything, isNot(contains('mediabrowser')));
      expect(everything, isNot(contains('token')));
      expect(everything, isNot(contains('jellyfin')));
    });

    test('asks GitHub for releases, and identifies only the app', () async {
      final repo = build();
      github.on(UpdateRepository.releasesUrl, json: <dynamic>[]);

      await repo.check();

      final sent = github.requests.single;
      expect(sent.uri.host, 'api.github.com');
      expect(sent.uri.path, '/repos/missing-foss/garfin/releases');
      // Measured 2026-08-06 against the real API: `releases/latest` answers 404
      // here, because it excludes pre-releases and every Garfin release is one.
      // The obvious endpoint would report "no releases yet" to every beta user
      // and look like a working feature while doing it.
      expect(sent.uri.path, isNot(endsWith('/latest')));
      expect(sent.headers['User-Agent'], '$appClientName/$appVersion');
      expect(sent.headers['Accept'], 'application/vnd.github+json');
    });

    test('one press, one request', () async {
      // The whole privacy argument for this feature is "never automatic". A
      // check that quietly retried would be two contacts for one press.
      final repo = build();
      github.on(UpdateRepository.releasesUrl, json: <dynamic>[]);

      await repo.check();

      expect(github.requests, hasLength(1));
    });
  });

  group('what it says', () {
    test('a newer release is available, with its tag and page', () async {
      final repo = build();
      github.on(UpdateRepository.releasesUrl, json: <dynamic>[release('v9.9.9')]);

      final result = await repo.check();

      expect(result.outcome, UpdateOutcome.available);
      expect(result.tag, 'v9.9.9');
      expect(result.url, contains('releases/tag/v9.9.9'));
    });

    test('the running version is up to date', () async {
      final repo = build();
      github.on(UpdateRepository.releasesUrl,
          json: <dynamic>[release('v$appVersion')]);

      expect((await repo.check()).outcome, UpdateOutcome.upToDate);
    });

    test('an older release does not count as an update', () async {
      final repo = build();
      github.on(UpdateRepository.releasesUrl, json: <dynamic>[release('v0.0.1')]);

      expect((await repo.check()).outcome, UpdateOutcome.upToDate);
    });

    test('no releases published is not a failure', () async {
      // True of Garfin itself until the first one ships, so a parent pressing
      // the button today should not be told something went wrong.
      final repo = build();
      github.on(UpdateRepository.releasesUrl, json: <dynamic>[]);

      expect((await repo.check()).outcome, UpdateOutcome.noReleases);
    });

    test('403 and 429 are rate limiting, not failure', () async {
      // Measured: anonymous callers get 60 an hour, per address. Behind a
      // shared connection that is reachable, and "try again later" is the
      // useful sentence — "something went wrong" is not.
      for (final status in [403, 429]) {
        final repo = build();
        github.on(UpdateRepository.releasesUrl,
            status: status, json: <String, Object?>{'message': 'rate limited'});

        expect((await repo.check()).outcome, UpdateOutcome.rateLimited,
            reason: '$status should read as rate limiting');
      }
    });

    test('a request that never arrives is offline, not failure', () async {
      final repo = build();
      github.on(UpdateRepository.releasesUrl,
          failWith: DioExceptionType.connectionError);

      expect((await repo.check()).outcome, UpdateOutcome.offline);
    });

    test('an answer that makes no sense is a failure', () async {
      for (final body in <Object>[
        <String, Object?>{'message': 'Not Found'}, // not a list
        <dynamic>[<String, Object?>{'no_tag_here': true}],
        <dynamic>[release('not-a-version')],
      ]) {
        final repo = build();
        github.on(UpdateRepository.releasesUrl, json: body);

        expect((await repo.check()).outcome, UpdateOutcome.failed,
            reason: 'unreadable body: $body');
      }
    });

    test('a 500 is a failure and not a rate limit', () async {
      final repo = build();
      github.on(UpdateRepository.releasesUrl, status: 500);

      expect((await repo.check()).outcome, UpdateOutcome.failed);
    });
  });

  group('version reading', () {
    test('a tag prefix does not hide the version', () {
      // Not hypothetical: the sibling project tags releases `android-v2.14.0`.
      // A parser that only survives its own repo's convention breaks by
      // silently reporting "up to date", which is the failure nobody notices.
      expect(UpdateRepository.parseVersion('v1.2.3'), [1, 2, 3]);
      expect(UpdateRepository.parseVersion('android-v2.14.0'), [2, 14, 0]);
      expect(UpdateRepository.parseVersion('1.2.3'), [1, 2, 3]);
      expect(UpdateRepository.parseVersion('v1.2.3-beta.4'), [1, 2, 3]);
      expect(UpdateRepository.parseVersion('nightly'), isNull);
    });

    test('components compare as numbers, not as text', () {
      // The bug this catches: '10' < '9' as strings, so a string comparison
      // stops offering updates at exactly the point a project gets popular.
      expect(UpdateRepository.isNewer([0, 10, 0], [0, 9, 0]), isTrue);
      expect(UpdateRepository.isNewer([1, 0, 0], [0, 99, 99]), isTrue);
      expect(UpdateRepository.isNewer([0, 1, 1], [0, 1, 0]), isTrue);
      expect(UpdateRepository.isNewer([0, 1, 0], [0, 1, 0]), isFalse);
      expect(UpdateRepository.isNewer([0, 0, 9], [0, 1, 0]), isFalse);
    });
  });
}
