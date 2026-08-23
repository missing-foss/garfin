// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';

import 'device_identity.dart';

/// Returns the access token to attach, or null when signed out.
///
/// A callback rather than a value so the interceptor picks up a sign-in or a
/// sign-out without the `Dio` instance being rebuilt underneath every in-flight
/// request.
typedef TokenReader = String? Function();

/// Attaches `Authorization: MediaBrowser …` to every request, in one place.
///
/// `docs/JELLYFIN-API.md`:
///
///     Authorization: MediaBrowser Token="…", Client="Garfin", Device="…",
///                                 DeviceId="…", Version="…"
///
/// The unauthenticated calls need it too — `AuthenticateByName` and the Quick
/// Connect exchange identify the device from this header, which is how the
/// session Jellyfin creates ends up attached to the right entry in
/// Dashboard → Devices. Those requests carry every field except `Token`.
class MediaBrowserAuthInterceptor extends Interceptor {
  MediaBrowserAuthInterceptor({
    required this.identity,
    required this.readToken,
  });

  final DeviceIdentity identity;
  final TokenReader readToken;

  /// The header name. Jellyfin also accepts `X-Emby-Authorization`; Garfin
  /// sends exactly one of the two, never both, so there is no chance of the
  /// server preferring a stale copy.
  static const headerName = 'Authorization';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Assignment, not `addAll` or a list append: a request that already carries
    // an Authorization header (a retry, or a caller that set one by hand) gets
    // it *replaced*. Two Authorization headers on one request is not "belt and
    // braces" — dio would join them with a comma and Jellyfin would parse the
    // pair as one malformed value.
    options.headers[headerName] = buildHeader(
      identity: identity,
      token: readToken(),
    );
    handler.next(options);
  }

  /// Builds the header value. Public so tests can assert on it without a
  /// round-trip through `Dio`.
  static String buildHeader({
    required DeviceIdentity identity,
    String? token,
  }) {
    final parts = <String>[
      // Token first when present, matching the documented form. Omitted rather
      // than sent empty when signed out: Jellyfin treats `Token=""` as an
      // attempt to authenticate with an empty token on some versions, which
      // answers 401 to calls that are supposed to be anonymous.
      if (token != null && token.isNotEmpty) 'Token="${_quote(token)}"',
      'Client="${_quote(identity.client)}"',
      'Device="${_quote(identity.deviceName)}"',
      'DeviceId="${_quote(identity.deviceId)}"',
      'Version="${_quote(identity.version)}"',
    ];
    return 'MediaBrowser ${parts.join(', ')}';
  }

  /// Makes a value safe to sit inside a quoted header parameter.
  ///
  /// The device name is the only field that is not ours — it comes from the
  /// platform — but sanitise all of them. A stray `"` would end the parameter
  /// early and let the rest of the value be read as further parameters; a bare
  /// newline would let it be read as a further *header*. Dropping the offending
  /// characters is right here: these values are labels, and a mangled label is
  /// better than a request Jellyfin rejects or misreads.
  static String _quote(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f"\\]'), '');
}
