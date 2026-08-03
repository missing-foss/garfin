// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/authentication_result.dart';
import '../models/jellyfin_user.dart';
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
  /// The caller owns the secret's lifetime and must not persist it — see
  /// [QuickConnectInitiation] and `QuickConnectSession`, which is what actually
  /// holds it.
  Future<QuickConnectInitiation> initiateQuickConnect({
    CancelToken? cancelToken,
  }) =>
      _call(() async {
        final response = await _dio.get<dynamic>(
          '/QuickConnect/Initiate',
          cancelToken: cancelToken,
        );
        return QuickConnectInitiation.fromJson(_asMap(response.data));
      });

  /// One poll of the pairing's state.
  ///
  /// A 404 here means the server has forgotten this secret — the code expired,
  /// or Quick Connect was switched off mid-pairing. That is
  /// [JellyfinErrorKind.quickConnectExpired] and not a generic not-found,
  /// because the honest answer to the user is "ask for a new code".
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
        onNotFound: JellyfinErrorKind.quickConnectExpired,
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
        onNotFound: JellyfinErrorKind.quickConnectExpired,
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

  Future<T> _call<T>(
    Future<T> Function() body, {
    JellyfinErrorKind? onNotFound,
  }) async {
    try {
      return await body();
    } on DioException catch (error) {
      final mapped = JellyfinException.fromDio(error);
      if (onNotFound != null && mapped.kind == JellyfinErrorKind.notFound) {
        return Future.error(
          JellyfinException(onNotFound, message: mapped.message),
        );
      }
      return Future.error(mapped);
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
