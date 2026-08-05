// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/authentication_result.dart';
import '../models/dto_json.dart';
import '../models/jellyfin_user.dart';
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
  /// A `Limit=0` query returns no items at all, just the count, so this is
  /// cheap enough to do per child.
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
  Future<LibraryPage> libraryPage({
    required String userId,
    required int startIndex,
    required int limit,
    List<String> itemTypes = const ['Movie', 'Series', 'BoxSet'],
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>(
          '/Items',
          queryParameters: <String, dynamic>{
            'userId': userId,
            'Recursive': true,
            'StartIndex': startIndex,
            'Limit': limit,
            'IncludeItemTypes': itemTypes.join(','),
            'Fields': 'Tags',
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
  Future<Map<String, dynamic>> fullItem({
    required String userId,
    required String itemId,
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>('/Users/$userId/Items/$itemId');
        return _asMap(response.data);
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
