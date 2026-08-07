// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';

import '../app_info.dart';
import '../logging.dart';

/// Asking GitHub whether there is a newer Garfin — **only when asked** (#66).
///
/// This is the one place Garfin contacts anything other than the user's own
/// Jellyfin server, so the shape of it is deliberate and `SECURITY.md` says so
/// too:
///
/// - **Never automatic.** No timer, no check on launch, no check after an
///   update. It runs when a finger lands on the button and at no other moment.
/// - **Anonymous.** No token, no cookies, no query parameters. The request
///   carries `Accept` and a `User-Agent` of `Garfin/<version>` — GitHub rejects
///   requests without a UA, and that string is the product and its version, not
///   the device, the server, or the person.
/// - **Nothing about the household leaves.** The URL is a constant naming a
///   public repository; the response is read for a tag and a link.
///
/// The version comparison is arithmetic on three numbers and nothing more —
/// `docs/DECISIONS.md` explains why that is enough and what it deliberately
/// cannot do.
class UpdateRepository {
  UpdateRepository({required this.dio});

  /// Not Jellyfin's client. See `update_providers.dart` — that one attaches an
  /// admin token to everything it sends.
  final Dio dio;

  /// **`/releases`, not `/releases/latest`.** Measured 2026-08-06 against the
  /// real API: `releases/latest` answers **404** for this repository, because it
  /// excludes pre-releases and every Garfin release so far is one. Using the
  /// obvious endpoint would have told every beta user "no releases yet"
  /// forever, and it would have looked like a working feature.
  ///
  /// `per_page=1` because the list comes back newest-first and one is all this
  /// asks for.
  static const releasesUrl =
      'https://api.github.com/repos/missing-foss/garfin/releases?per_page=1';

  /// One call. Returns what to say, never throws.
  ///
  /// Every outcome is a value rather than an exception because *all* of them
  /// are ordinary here: an update check that fails is not an error condition of
  /// the app, it is one of the things a check can say.
  Future<UpdateCheck> check() async {
    try {
      final response = await dio.get<Object?>(
        releasesUrl,
        options: Options(
          headers: <String, String>{
            'Accept': 'application/vnd.github+json',
            // GitHub answers 403 to a request with no User-Agent. This one
            // names the product and its version and nothing else.
            'User-Agent': '$appClientName/$appVersion',
          },
          // Every status is handled below; dio must not turn 403 into a throw
          // that hides which 403 it was.
          validateStatus: (_) => true,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status == 403 || status == 429) {
        // Measured: anonymous callers get 60 requests an hour, per IP. A parent
        // pressing a button will never see this; a shared NAT might.
        log.info('update check rate-limited ($status)');
        return const UpdateCheck(UpdateOutcome.rateLimited);
      }
      if (status != 200) {
        log.warning('update check answered $status');
        return const UpdateCheck(UpdateOutcome.failed);
      }

      final body = response.data;
      // Two different things, and folding them together was the first version
      // of this: an empty *list* is a repository with nothing published, which
      // is true of Garfin itself until the first release ships and is not a
      // failure. A 200 that is not a list at all is an answer this code cannot
      // read, and calling that "no releases yet" would report a broken parser
      // as ordinary good news.
      if (body is! List) {
        log.warning('update check got a ${body.runtimeType}, not a list');
        return const UpdateCheck(UpdateOutcome.failed);
      }
      if (body.isEmpty) return const UpdateCheck(UpdateOutcome.noReleases);

      final newest = body.first;
      if (newest is! Map) return const UpdateCheck(UpdateOutcome.failed);
      final tag = newest['tag_name'];
      final url = newest['html_url'];
      if (tag is! String || url is! String) {
        return const UpdateCheck(UpdateOutcome.failed);
      }

      final theirs = parseVersion(tag);
      final ours = parseVersion(appVersion);
      if (theirs == null || ours == null) {
        log.warning('update check could not read a version from "$tag"');
        return const UpdateCheck(UpdateOutcome.failed);
      }

      return isNewer(theirs, ours)
          ? UpdateCheck(UpdateOutcome.available, tag: tag, url: url)
          : const UpdateCheck(UpdateOutcome.upToDate);
    } on DioException catch (error) {
      log.info('update check could not reach GitHub: ${error.type}');
      return const UpdateCheck(UpdateOutcome.offline);
    } on Object catch (error, stack) {
      log.warning('update check failed: ${error.runtimeType}', error, stack);
      return const UpdateCheck(UpdateOutcome.failed);
    }
  }

  /// The first `N.N.N` in a tag, or null.
  ///
  /// A regex rather than `split('.')` on a stripped `v`, because a tag prefix is
  /// real and not hypothetical: the sibling project tags releases
  /// `android-v2.14.0`. Garfin's own workflow requires `vX.Y.Z`, but a parser
  /// that only survives its own repository's convention is a parser that breaks
  /// the first time the convention changes — and it would break by silently
  /// reporting "up to date".
  static List<int>? parseVersion(String tag) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(tag);
    if (match == null) return null;
    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  /// Strictly greater, component by component.
  ///
  /// Deliberately blind to pre-release suffixes: `v0.2.0-beta.1` and `v0.2.0`
  /// compare equal. The consequence is that a beta and the release it precedes
  /// are indistinguishable here, which is the safe direction — it can say
  /// "you're up to date" a day early, never "there's an update" that isn't one.
  static bool isNewer(List<int> theirs, List<int> ours) {
    for (var i = 0; i < 3; i++) {
      if (theirs[i] != ours[i]) return theirs[i] > ours[i];
    }
    return false;
  }
}

enum UpdateOutcome {
  /// A newer release exists. Carries its tag and its page.
  available,

  /// Asked, answered, nothing newer.
  upToDate,

  /// The repository has no published release. Not a failure.
  noReleases,

  /// GitHub's anonymous quota, 60 an hour per IP.
  rateLimited,

  /// The request never got there.
  offline,

  /// It got there and the answer made no sense.
  failed,
}

class UpdateCheck {
  const UpdateCheck(this.outcome, {this.tag, this.url});

  final UpdateOutcome outcome;

  /// The release's tag as GitHub spells it — shown to the user verbatim rather
  /// than reformatted, so what the About screen says matches what the releases
  /// page says.
  final String? tag;
  final String? url;
}
