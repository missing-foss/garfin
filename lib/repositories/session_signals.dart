// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';

/// What every authenticated call learns about the session, told to whoever
/// owns it.
///
/// **The session used to be checked once**, as the auth controller was built,
/// and never again. Ten seconds without Wi-Fi at launch left "can't reach the
/// server" above a working app until a restart; a device revoked from the
/// dashboard left every screen saying "unauthorized" over cached data, with the
/// dead token still in storage. Every call already knew the answer — a 2xx
/// says the server is there, a 401 says the token is not honoured — and
/// nothing listened.
///
/// A relay rather than a direct line to `AuthController`, because the
/// controller's own repository is built from the same client factory: wiring
/// the factory to the controller would make each depend on the other. The
/// controller attaches itself here once it exists, and until then a signal
/// goes nowhere.
class SessionSignals {
  void Function()? _onUnauthorized;
  void Function()? _onReachable;

  void attach({
    required void Function() onUnauthorized,
    required void Function() onReachable,
  }) {
    _onUnauthorized = onUnauthorized;
    _onReachable = onReachable;
  }

  void detach() {
    _onUnauthorized = null;
    _onReachable = null;
  }

  void unauthorized() => _onUnauthorized?.call();
  void reachable() => _onReachable?.call();
}

/// Listens to an **authenticated** client for the two answers the session
/// turns on.
///
/// Only ever added where a token is sent. A 401 to a sign-in attempt is a
/// wrong password, not a revoked session, and must not sign anyone out.
class SessionSignalInterceptor extends Interceptor {
  SessionSignalInterceptor(this._signals);

  final SessionSignals _signals;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _signals.reachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) _signals.unauthorized();
    handler.next(err);
  }
}
