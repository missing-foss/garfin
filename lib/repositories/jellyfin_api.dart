// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/active_session.dart';
import '../models/authentication_result.dart';
import '../models/dto_json.dart';
import '../models/jellyfin_user.dart';
import '../models/library_filters.dart';
import '../models/library_item.dart';
import '../models/library_page.dart';
import '../models/parental_rating.dart';
import '../models/quick_connect.dart';
import 'device_identity.dart';
import 'jellyfin_exception.dart';
import 'media_browser_auth.dart';

/// The Jellyfin HTTP surface Garfin needs to sign in.
///
/// This is the only place in the app that speaks HTTP for authentication.
/// Widgets never call it directly — they go through the providers, which go
/// through `AuthRepository` (`CLAUDE.md` § Conventions).
///
/// Every method converts `DioException` into [JellyfinException] on the way
/// out, so nothing above this layer has to know about dio and nothing below it
/// can leak a URI with a `?secret=` in it into an error a caller might log.
class JellyfinApi {
  JellyfinApi(this._dio);

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  /// Whether the server offers Quick Connect.
  ///
  /// False hides the tab rather than letting `Initiate` fail — a disabled
  /// feature should not look like a broken one.
  Future<bool> quickConnectEnabled() => _call(() async {
        final response = await _dio.get<dynamic>('/QuickConnect/Enabled');
        // The endpoint answers a bare JSON boolean. Some proxies hand it back
        // as the string "true"; accept both rather than reading a stray quote
        // as "Quick Connect is off".
        final data = response.data;
        if (data is bool) return data;
        return data.toString().trim().toLowerCase() == 'true';
      });

  /// Starts a pairing and returns the six-digit code plus the secret.
  ///
  /// **POST, not GET.** `docs/JELLYFIN-API.md` and issue #17 both say
  /// `GET /QuickConnect/Initiate`, and measured against 10.11.11 the GET does
  /// still answer 200 — but the server's own `/api-docs/openapi.json` lists
  /// **only** `post` for this route. GET is an undocumented survivor, so it is
  /// the one that can disappear in a point release. POST is the contract.
  ///
  /// The `Authorization` header matters here even though the call is anonymous:
  /// measured, the server echoes `DeviceId`, `DeviceName`, `AppName` and
  /// `AppVersion` straight back out of it, which is what the user sees when
  /// they are asked to approve the code.
  ///
  /// The caller owns the secret's lifetime and must not persist it — see
  /// [QuickConnectInitiation] and `QuickConnectSession`, which is what actually
  /// holds it.
  Future<QuickConnectInitiation> initiateQuickConnect({
    CancelToken? cancelToken,
  }) =>
      _call(
        () async {
          final response = await _dio.post<dynamic>(
            '/QuickConnect/Initiate',
            cancelToken: cancelToken,
          );
          return QuickConnectInitiation.fromJson(_asMap(response.data));
        },
        // A 401 here is not "wrong credentials" — measured, the server answers
        // 401 "Quick connect is disabled" when the feature is off. That happens
        // when it is switched off between the `Enabled` probe and this call, and
        // telling the user their password was wrong would send them off fixing
        // the wrong thing. A missing route means the same to them: no Quick
        // Connect on this server, use the password tab.
        remap: const {
          JellyfinErrorKind.unauthorized:
              JellyfinErrorKind.quickConnectUnavailable,
          JellyfinErrorKind.notFound:
              JellyfinErrorKind.quickConnectUnavailable,
        },
      );

  /// One poll of the pairing's state.
  ///
  /// Measured on 10.11.11: an unknown secret answers `404 "Unknown secret"`,
  /// and the feature being switched off mid-pairing answers
  /// `401 "Quick connect is disabled"`. Those are different sentences to the
  /// user — "ask for a new code" against "use a password instead" — so they map
  /// to different kinds rather than to a generic failure.
  Future<QuickConnectStatus> quickConnectStatus(
    String secret, {
    CancelToken? cancelToken,
  }) =>
      _call(
        () async {
          final response = await _dio.get<dynamic>(
            '/QuickConnect/Connect',
            queryParameters: {'secret': secret},
            cancelToken: cancelToken,
          );
          return QuickConnectStatus.fromJson(_asMap(response.data));
        },
        remap: const {
          JellyfinErrorKind.notFound: JellyfinErrorKind.quickConnectExpired,
          JellyfinErrorKind.unauthorized:
              JellyfinErrorKind.quickConnectUnavailable,
        },
      );

  /// Trades an approved secret for an access token.
  Future<AuthenticationResult> authenticateWithQuickConnect(
    String secret, {
    CancelToken? cancelToken,
  }) =>
      _call(
        () async {
          final response = await _dio.post<dynamic>(
            '/Users/AuthenticateWithQuickConnect',
            data: {'Secret': secret},
            cancelToken: cancelToken,
          );
          return AuthenticationResult.fromJson(_asMap(response.data));
        },
        // Measured: trading a secret that has not been approved yet answers
        // 404. That should not happen — the poll gates this call — but if the
        // pairing is raced or the secret has aged out, "ask for a new code" is
        // the right thing to say.
        remap: const {
          JellyfinErrorKind.notFound: JellyfinErrorKind.quickConnectExpired,
          JellyfinErrorKind.unauthorized:
              JellyfinErrorKind.quickConnectUnavailable,
        },
      );

  /// Approves a Quick Connect code **on another user's behalf** (#40).
  ///
  /// The parent types the six digits their child's device is showing, Garfin
  /// approves it as the administrator, and the child's device exchanges its own
  /// secret for a token belonging to the **child**. Measured on 10.11.11: the
  /// resulting session is the child's, `IsAdministrator: false`, and no password
  /// is typed on the child's device — one the child need never be told.
  ///
  /// **`userId` is the whole feature, and the privilege boundary is the
  /// server's.** A non-admin token pointing `userId` at an administrator is
  /// refused with **403**; the same token approving for itself succeeds. Garfin
  /// does not re-implement that check, because a check it implemented would be
  /// the one that could be wrong.
  ///
  /// This is not a policy write. `Authorize` mints a session; ground rule 8 is
  /// about `POST /Users/{id}/Policy` and its full-object replace, and none of
  /// that risk is in play here.
  ///
  /// **Garfin never sees the secret.** Only the requesting device holds it,
  /// which is also why nothing can be shown about the device being approved —
  /// see the failure map below and `docs/JELLYFIN-API.md`.
  Future<void> approveQuickConnect({
    required String code,
    required String userId,
  }) {
    // **`Authorize` fails open to the approving administrator.** Measured on
    // 10.11.11, and it is the reason this guard exists rather than a general
    // validator:
    //
    //     userId=<child>       -> 200, the device gets the CHILD's session
    //     userId=<all zeroes>  -> 200, the device gets the ADMIN's session
    //     userId omitted       -> 200, the device gets the ADMIN's session
    //     userId=              -> 200, the device gets the ADMIN's session
    //
    // No error in any of those, and `JellyfinUser.fromJson` defaults a missing
    // `Id` to the empty string — so one malformed `/Users` row would turn a
    // child's card into a button that hands an administrator session to the
    // tablet, while the sheet says the child was signed in.
    //
    // This is not re-implementing the server's privilege check: that check is
    // the 403 a non-admin gets, and it stays the server's. This is declining to
    // send a request whose meaning Garfin does not intend. Same family as
    // `fullItem` comparing the id it got back with the one it asked for — the
    // all-zero GUID again, on a route that mints sessions instead of returning
    // a folder.
    final trimmed = userId.trim();
    if (trimmed.isEmpty || trimmed.replaceAll('-', '').replaceAll('0', '').isEmpty) {
      return Future.error(
        const JellyfinException(
          JellyfinErrorKind.unusableUserId,
          message: 'refusing to approve without a usable user id',
        ),
      );
    }

    return _call(
        () async {
          await _dio.post<dynamic>(
            '/QuickConnect/Authorize',
            // `trimmed`, not `userId`: the value that was checked and the value
            // that goes out should be the same thing. Whitespace here could
            // only ever produce a server-side 400 — never the fail-open above —
            // but a guard that validates one string and sends another is the
            // shape the next bug takes.
            queryParameters: <String, dynamic>{
              'code': code,
              'userId': trimmed,
            },
          );
        },
        // Measured on 10.11.11, each case on its **own fresh code**:
        //
        //     a code nobody asked for            -> 404
        //     a well-formed but absent user id   -> 400
        //     the same code twice                -> 500
        //
        // An earlier reading of this said the last two both answered 500. That
        // was a confounded measurement — the absent-user case reused a code
        // that a previous step had already spent, so the 500 came from the
        // code, not the id. The UI still offers "it may already have been used"
        // as a reason to check rather than asserting it, because a 500 has no
        // other documented meaning here; the difference is that the doc no
        // longer claims the server cannot tell them apart.
        remap: const {
          JellyfinErrorKind.notFound: JellyfinErrorKind.quickConnectExpired,
          JellyfinErrorKind.unauthorized:
              JellyfinErrorKind.quickConnectUnavailable,
        },
      );
  }

  /// The password fallback.
  Future<AuthenticationResult> authenticateByName({
    required String username,
    required String password,
  }) =>
      _call(() async {
        final response = await _dio.post<dynamic>(
          '/Users/AuthenticateByName',
          // `Pw` is the field Jellyfin reads. `Password` also exists and is the
          // legacy SHA-1 form — sending it would downgrade the exchange.
          data: {'Username': username, 'Pw': password},
        );
        return AuthenticationResult.fromJson(_asMap(response.data));
      });

  /// The user behind the token currently attached by the interceptor.
  ///
  /// Used to re-check `Policy.IsAdministrator` when a stored session is
  /// restored: rights can be taken away on the server between two launches, and
  /// ground rule 7 is about the account Garfin is *using*, not only the one it
  /// signed in with.
  Future<JellyfinUser> currentUser() => _call(() async {
        final response = await _dio.get<dynamic>('/Users/Me');
        return JellyfinUser.fromJson(_asMap(response.data));
      });

  /// Every user on the server, with their policy.
  ///
  /// Measured on 10.11.11: this answers **200 with every user's `Policy`
  /// populated even for a non-admin token** — there is no 403. So nothing here
  /// can be relied on to catch a wrong account; ground rule 7's check at
  /// sign-in is the only thing standing between one and a Kids screen that
  /// looks entirely functional.
  Future<List<JellyfinUser>> users() => _call(() async {
        final response = await _dio.get<dynamic>('/Users');
        final data = response.data;
        if (data is! List) {
          throw const JellyfinException(
            JellyfinErrorKind.server,
            message: 'unexpected response shape',
          );
        }
        return data
            .whereType<Map<String, dynamic>>()
            .map(JellyfinUser.fromJson)
            .toList(growable: false);
      });

  /// The server's parental rating ladder for this install's locale.
  ///
  /// Fetched, never hardcoded — the list differs by locale, and entry zero has
  /// no `Value`. See [ParentalRatingLadder].
  Future<ParentalRatingLadder> parentalRatings() => _call(() async {
        final response = await _dio.get<dynamic>('/Localization/ParentalRatings');
        final data = response.data;
        if (data is! List) {
          throw const JellyfinException(
            JellyfinErrorKind.server,
            message: 'unexpected response shape',
          );
        }
        return ParentalRatingLadder.fromJson(data);
      });

  /// How many items [userId] can see, **as the server counts them**.
  ///
  /// Ground rule 4: never compute visibility client-side. This asks the server
  /// twice — once as the admin for the total, once as the child — and lets it
  /// apply the policy, including the rating cap that silently overrides tags.
  /// `Limit=0` returns no items at all, just the count. **That makes the
  /// payload small, not the work** — this comment used to draw the second
  /// conclusion from the first and say it was "cheap enough to do per child",
  /// which was never measured and is false. Measured on 10.11.11: 19 ms when
  /// the child can see 1 title, 214 ms at 1000, 538 ms at 2000, and the same
  /// again for the administrator, who sees everything. The cost tracks the
  /// **result set**, so it grows as a parent shares more. See
  /// `docs/JELLYFIN-API.md` § Counting what a user can see, and #68.
  ///
  /// `Recursive=true` is required or the count covers only top-level items.
  Future<int> visibleItemCount({required String userId}) => _call(() async {
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'Limit': 0,
            // Folders and collections would inflate the number with things a
            // parent does not think of as "titles".
            'IncludeItemTypes': 'Movie,Series',
          },
        );
        return readInt(_asMap(response.data), 'TotalRecordCount') ?? 0;
      });

  /// One page of the library, as a given user sees it.
  ///
  /// `Fields=Tags` is not optional: without it the `Tags` key is **absent**
  /// from every item, and the grid's whole shared/not-shared partition is
  /// computed from it. Measured on 10.11.11.
  ///
  /// [filters] are applied by the **server**. The delimiters are measured, not
  /// guessed, and they disagree with each other: `genres=` takes `|` and reads a
  /// comma as part of the value (`genres=Family,Comedy` answers **0**), while
  /// `years=` takes a comma and answers **400** to a pipe. `IncludeItemTypes`
  /// takes a comma. One wrong delimiter fails loudly and the other silently, so
  /// each is pinned by a test.
  Future<LibraryPage> libraryPage({
    required String userId,
    required int startIndex,
    required int limit,
    List<String> itemTypes = const ['Movie', 'Series', 'BoxSet'],
    LibraryFilters filters = const LibraryFilters(),
    int? maxParentalRating,
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'StartIndex': startIndex,
            'Limit': limit,
            'IncludeItemTypes':
                (filters.type == null ? itemTypes : [filters.type!]).join(','),
            // Measured (#73): title only — not the overview, the cast, tags
            // or genres — matching any substring, case- and
            // accent-insensitively, and ANDing with every filter below rather
            // than replacing them. `Recursive` above is load-bearing for it:
            // without it the same query answers with folders, not films.
            //
            // Trimmed and omitted when empty, because whitespace is not a
            // search — the server returns the whole library for it, and a
            // request that filters nothing should not look like one that does.
            if (filters.hasSearch) 'searchTerm': filters.searchTerm!.trim(),
            if (filters.genre != null) 'genres': filters.genre,
            if (filters.decade != null)
              'years': filters.decadeYears.join(','),
            // The child's cap goes out as the **number** from their policy.
            // Measured: `maxOfficialRating` accepts the numeric value as well
            // as a name, and this locale's ladder has five names sharing value
            // 0 — so a name would mean choosing one of them arbitrarily. It
            // also fails safe against the other measured behaviour: a value the
            // server cannot parse filters *nothing*, silently.
            if (filters.withinCap && maxParentalRating != null)
              'maxOfficialRating': maxParentalRating,
            // `ChildCount` is **absent** without asking for it, the same way
            // `Tags` is. Measured on 10.11.11: `Fields=Tags` alone returns no
            // `ChildCount` at all, so `LibraryItem.childCount` was always null
            // and the collection count badge `docs/UI-SPEC.md` asks for — which
            // `library_tile.dart` guards on that field being non-null — had
            // never once rendered.
            'Fields': 'Tags,ChildCount',
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
          },
        );
        final data = _asMap(response.data);
        final items = readField(data, 'Items');
        return LibraryPage(
          items: items is List
              ? items
                  .whereType<Map<String, dynamic>>()
                  .map(LibraryItem.fromJson)
                  .toList(growable: false)
              : const [],
          totalRecordCount: readInt(data, 'TotalRecordCount') ?? 0,
          startIndex: startIndex,
        );
      });

  /// The genres present in this library, for the filter chip.
  ///
  /// Measured: this is an **index**, not a scan of the items — after writing
  /// genres onto items directly it answered empty until a library refresh ran,
  /// then listed them within five seconds. So an empty answer means "nothing
  /// indexed", which is not the same as "no genres", and the chip hides itself
  /// rather than claiming the library has none.
  Future<List<String>> genres({required String userId}) => _call(() async {
        final response = await _dio.get<dynamic>(
          '/Genres',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'IncludeItemTypes': 'Movie,Series',
            'SortBy': 'SortName',
          },
        );
        return _itemsOf(response.data)
            .map((item) => item.name)
            .where((name) => name.isNotEmpty)
            .toList(growable: false);
      });

  /// The production years present, which the Decade chip groups by ten.
  Future<List<int>> years({required String userId}) => _call(() async {
        final response = await _dio.get<dynamic>(
          '/Years',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'SortBy': 'SortName',
          },
        );
        return _itemsOf(response.data)
            .map((item) => int.tryParse(item.name))
            .whereType<int>()
            .toList(growable: false);
      });

  /// Of [ids], the ones the server shows to [userId].
  ///
  /// **This is how visibility is decided, and it is the server deciding.**
  /// Ground rule 4 forbids working it out from the item's rating and the
  /// child's cap, which fails silently on unrated items, on a non-US ladder,
  /// and on anything hidden for a reason that is not the cap at all — a folder
  /// permission looks identical from here.
  ///
  /// Bounded by the page: `ids` is comma-delimited, so this asks about the
  /// twenty-odd items on screen rather than the whole library.
  ///
  /// **No `Recursive=true`, deliberately.** Every other `/Items` call here
  /// passes it, so its absence looks like an oversight — it is not. `ids=` is
  /// its own lookup and does not consult the recursion flag. Measured on
  /// 10.11.11 with items nested inside a library: three ids in, three back for
  /// the admin and two for a capped child, identical with and without it.
  ///
  /// Adding it would be harmless but would enshrine a wrong reason, and the
  /// failure it would appear to fix is worth knowing: had `ids=` needed
  /// recursion, this would return an empty set — a *successful* empty response,
  /// which the caller's fallback does not catch — and every labelled item on
  /// the grid would render as held back.
  Future<Set<String>> visibleIds({
    required String userId,
    required List<String> ids,
  }) =>
      _call(() async {
        if (ids.isEmpty) return <String>{};
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'ids': ids.join(','),
            'Limit': ids.length,
            // Nothing here is rendered — only membership is read — so ask for
            // as little as the endpoint will send.
            'enableImages': false,
            'enableUserData': false,
          },
        );
        final data = _asMap(response.data);
        final items = readField(data, 'Items');
        if (items is! List) return <String>{};
        return items
            .whereType<Map<String, dynamic>>()
            .map((item) => readString(item, 'Id') ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      });

  /// How many items carry [tag], as the server counts them.
  ///
  /// A library query, not a visibility computation — the same distinction
  /// ground rule 1 draws for the last-item warning. No cap enters into it.
  ///
  /// **[itemTypes] is load-bearing and its default must not be widened.**
  /// Measured on 10.11.11 (#53): a label written to one *series* is inherited
  /// by its seasons and episodes, which report it and are matched by `tags=`.
  /// One write to one six-episode series answers:
  ///
  ///     Movie,Series,BoxSet -> 1        Season -> 2
  ///     Episode             -> 6        no type filter -> 9
  ///
  /// This count is what ground rule 1's last-item hard warning is built on —
  /// the warning that stops a parent taking a label off the last item carrying
  /// it and leaving the child seeing *nothing*. Include `Episode` or `Season`
  /// and one series contributes nine instead of one, `count <= 1` stops being
  /// reachable in any library that has a series in it, and the warning silently
  /// never fires again. `test/tagged_item_count_test.dart` pins it.
  Future<int> taggedItemCount({
    required String userId,
    required String tag,
    List<String> itemTypes = const ['Movie', 'Series', 'BoxSet'],
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'Limit': 0,
            'tags': tag,
            'IncludeItemTypes': itemTypes.join(','),
          },
        );
        return readInt(_asMap(response.data), 'TotalRecordCount') ?? 0;
      });

  /// Every BoxSet on the server, for the reverse index a sheet needs.
  ///
  /// One call; the members come from [collectionMembers], one call each.
  Future<List<LibraryItem>> collections({
    required String userId,
    int limit = 500,
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'Limit': limit,
            'IncludeItemTypes': 'BoxSet',
            'Fields': 'Tags,ChildCount',
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
          },
        );
        return _itemsOf(response.data);
      });

  /// What is inside a collection.
  ///
  /// Measured on 10.11.11: `userId` and `Recursive=true` change nothing here —
  /// `parentId` is its own lookup — but `Fields=Tags` is required exactly as it
  /// is elsewhere, and without it the `Tags` key is **absent** rather than
  /// empty, which would report every member as unlabelled.
  ///
  /// The rows carry `Name`, `ProductionYear` and `OfficialRating` unasked, so
  /// the "keep the set together?" dialog can list the other members with their
  /// ratings off this one query.
  ///
  /// **These rows are for reading only.** They are list results — 16 fields
  /// against 41 from a single-item `GET` on a BoxSet — and posting one back is
  /// the wipe ground rule 2 exists to prevent. Nothing in the write path
  /// accepts them; it takes ids. See [replaceItem].
  Future<List<LibraryItem>> collectionMembers({
    required String userId,
    required String collectionId,
    int limit = 500,
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'parentId': collectionId,
            'Limit': limit,
            'Fields': 'Tags',
          },
        );
        return _itemsOf(response.data);
      });

  /// Every signed-in device the server knows about.
  ///
  /// **`userId` does not filter this.** Measured on 10.11.11:
  /// `/Sessions?userId={child}` answers with *every* session, the admin's
  /// included — another parameter that is accepted and ignored rather than
  /// rejected, like `ancestorIds` on `/Items`. So the caller filters by
  /// `UserId` itself, and a screen that trusted the parameter would show one
  /// child's card with somebody else's session under it.
  ///
  /// `activeWithinSeconds` **does** work, and is a recency filter rather than a
  /// liveness one: at 1 second the idle admin session drops out while the
  /// child's remains.
  Future<List<ActiveSession>> sessions() => _call(() async {
        final response = await _dio.get<dynamic>('/Sessions');
        final data = response.data;
        if (data is! List) {
          throw const JellyfinException(
            JellyfinErrorKind.server,
            message: 'unexpected response shape',
          );
        }
        return data
            .whereType<Map<String, dynamic>>()
            .map(ActiveSession.fromJson)
            .whereType<ActiveSession>()
            .toList(growable: false);
      });

  /// Puts a line of text on a session's screen.
  ///
  /// **A 204 means the server accepted it, not that anybody saw it.** Measured:
  /// this answers 204 against a session whose `SupportsRemoteControl` is false
  /// and which cannot display anything. The copy says what was sent.
  Future<void> sendSessionMessage({
    required String sessionId,
    required String text,
    required String header,
  }) =>
      _call(() async {
        await _dio.post<dynamic>(
          '/Sessions/$sessionId/Message',
          data: <String, dynamic>{
            'Text': text,
            'Header': header,
            'TimeoutMs': 8000,
          },
        );
      });

  /// Asks a session to stop whatever it is playing.
  ///
  /// Same caveat as [sendSessionMessage]: 204 is acceptance, not compliance.
  Future<void> stopSessionPlayback({required String sessionId}) =>
      _call(() async {
        await _dio.post<dynamic>('/Sessions/$sessionId/Playing/Stop');
      });

  /// Ends a session by revoking its device.
  ///
  /// Measured: the token goes from 200 to **401** and the session disappears
  /// from `/Sessions`. Keyed on the **device**, not the session id — an unknown
  /// id, session id or nonsense alike, answers **404** and ends nothing.
  ///
  /// **Not a policy write** — no full-object replace, so ground rule 8 is
  /// untouched, the same as the Quick Connect approval in #40.
  ///
  /// It works on *any* device, including the one Garfin is running on:
  /// measured, an admin deleting its own device gets 204 and its very next
  /// request answers 401. The caller must never offer this for
  /// `DeviceIdentity.deviceId`.
  Future<void> endSession({required String deviceId}) => _call(() async {
        await _dio.delete<dynamic>(
          '/Devices',
          queryParameters: <String, dynamic>{'id': deviceId},
        );
      });

  /// The complete item, as the only legal source for a write.
  ///
  /// **Ground rule 2 starts here.** `POST /Items/{id}` replaces the whole
  /// object, so the thing posted back has to be the whole object. Measured on
  /// 10.11.11: this returns **52 fields with no `Fields` parameter** — asking
  /// for every field explicitly adds nothing — while a *list* query returns
  /// **19 of 52**, dropping `Overview`, `ProviderIds`, `Genres`, `People`,
  /// `Studios`, `Tags`, `Path`, `SortName` and 25 more.
  ///
  /// Posting a list result back is the wipe the rule exists to prevent. That is
  /// why nothing in the write path accepts an item object — see [replaceItem].
  ///
  /// **It also checks that the item it got back is the one it asked for**, which
  /// is not paranoia about a well-behaved endpoint. Measured on 10.11.11: a
  /// well-formed GUID that does not exist answers 404 — *except* the all-zero
  /// one, which answers **200 with the root "Media Folders" object**. A caller
  /// that trusted the status, or trusted that a JSON object came back, would
  /// then post the root folder's body to `/Items/00000…`. Comparing the `Id` is
  /// one line and it fails closed.
  ///
  /// **[itemId] must be canonical** — 32 hex digits, lower case, no dashes, as
  /// every id in this app is, because every one of them came out of a server
  /// response. Jellyfin accepts a dashed or upper-case GUID and answers with the
  /// canonical form, so the string comparison below would reject a *correct*
  /// item. That fails closed — a refused read, never a wrong write — but it
  /// would be a puzzling afternoon for whoever first hands this an id typed by
  /// hand or lifted out of a deep link.
  Future<Map<String, dynamic>> fullItem({
    required String userId,
    required String itemId,
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>('/Users/$userId/Items/$itemId');
        final item = _asMap(response.data);
        if (readString(item, 'Id') != itemId) {
          throw const JellyfinException(
            JellyfinErrorKind.notFound,
            message: 'the server answered with a different item',
          );
        }
        return item;
      });

  /// Posts a complete item back.
  ///
  /// Takes the raw map deliberately, and never a typed model: a typed model is
  /// exactly how a field goes missing from a full-object replace. Whatever came
  /// back from [fullItem] goes back unchanged apart from the one key being
  /// altered.
  ///
  /// Measured round-trip on 10.11.11 — `GET`, add one tag, `POST`, re-`GET`:
  /// 52 fields before and after, none lost, none gained, and only `Tags` and
  /// the server's own `Etag` different. Removal is symmetric.
  Future<void> replaceItem({
    required String itemId,
    required Map<String, dynamic> item,
  }) =>
      _call(() async {
        await _dio.post<dynamic>('/Items/$itemId', data: item);
      });

  /// Asks the server to re-read an item's metadata after a write.
  ///
  /// Settings → Labels → *refresh metadata after write*, and it is optional
  /// because it is slow, not because it is risky — **as long as it stays this
  /// exact call**. Measured on 10.11.11:
  ///
  /// | call | Garfin's tag |
  /// |---|---|
  /// | `Refresh?metadataRefreshMode=FullRefresh` | **survives** |
  /// | the same, plus `replaceAllMetadata=true` | **wiped** |
  ///
  /// So the dangerous parameter is not a flag on this method, not a default,
  /// and not reachable from a caller: it is absent. A refresh that deleted the
  /// label the write had just created would be the app undoing its own work,
  /// silently, and the only sign would be a child who cannot see the film they
  /// were just given.
  Future<void> refreshItem({required String itemId}) => _call(() async {
        await _dio.post<dynamic>(
          '/Items/$itemId/Refresh',
          queryParameters: <String, dynamic>{
            'metadataRefreshMode': 'FullRefresh',
          },
        );
      });

  /// Runs one call, converting dio's exception into Garfin's.
  ///
  /// [remap] lets an endpoint say what a status code means *there*. The same
  /// 401 is "wrong password" on `AuthenticateByName` and "Quick Connect is
  /// switched off" on the Quick Connect routes, and the user needs to be told
  /// the second one, not the first.
  Future<T> _call<T>(
    Future<T> Function() body, {
    Map<JellyfinErrorKind, JellyfinErrorKind>? remap,
  }) async {
    try {
      return await body();
    } on DioException catch (error) {
      final mapped = JellyfinException.fromDio(error);
      final remapped = remap?[mapped.kind];
      return Future.error(
        remapped == null
            ? mapped
            : JellyfinException(remapped, message: mapped.message),
      );
    }
  }

  /// The `Items` array of a list response, as models.
  static List<LibraryItem> _itemsOf(dynamic data) {
    final items = readField(_asMap(data), 'Items');
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(LibraryItem.fromJson)
        .toList(growable: false);
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    // A body that is not the JSON object we expected means we are talking to
    // something that is not this endpoint — a captive portal, a reverse proxy
    // error page, or a different product entirely.
    throw const JellyfinException(
      JellyfinErrorKind.server,
      message: 'unexpected response shape',
    );
  }
}

/// Builds a [JellyfinApi] against a given server, wiring the one auth
/// interceptor.
///
/// A factory rather than a single long-lived client because the server address
/// is not known until the user types it, and it can change afterwards from
/// Settings.
class JellyfinApiFactory {
  const JellyfinApiFactory({
    required this.identity,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 20),
    this.adapter,
  });

  final DeviceIdentity identity;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Replaces dio's transport.
  ///
  /// Exists so tests can drive the real client — interceptor, query building,
  /// parsing and error mapping — against scripted responses instead of stubbing
  /// [JellyfinApi] itself. Stubbing the API class would leave exactly the layer
  /// the ground rules live in untested: whether the `Authorization` header is
  /// attached once, and whether the Quick Connect secret goes where it should.
  @visibleForTesting
  final HttpClientAdapter? adapter;

  JellyfinApi create({required String baseUrl, TokenReader? readToken}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        // Jellyfin answers JSON everywhere Garfin looks. Being explicit stops a
        // reverse proxy content-negotiating us into XML.
        headers: const {'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
    );
    if (adapter != null) dio.httpClientAdapter = adapter!;
    dio.interceptors.add(
      MediaBrowserAuthInterceptor(
        identity: identity,
        readToken: readToken ?? () => null,
      ),
    );
    return JellyfinApi(dio);
  }
}
