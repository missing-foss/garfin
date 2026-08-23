// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/jellyfin_exception.dart';
import '../repositories/quick_connect_session.dart';
import '../repositories/server_settings_store.dart';
import 'app_providers.dart';
import 'auth_providers.dart';

/// Where the sign-in screen has got to.
class SignInState {
  const SignInState({
    this.serverUrl,
    this.quickConnectAvailable = false,
    this.busy = false,
    this.error,
    this.malformedUrl = false,
    this.credentialsDropped = false,
  });

  /// Set once an address has been accepted *and* answered. Null means the
  /// screen is still on the address step.
  final String? serverUrl;

  /// False hides the Quick Connect tab rather than letting `Initiate` fail —
  /// issue #17, and `docs/JELLYFIN-API.md`.
  final bool quickConnectAvailable;

  final bool busy;

  /// The last failure, for the screen to translate. Never server text.
  final JellyfinException? error;

  /// The address could not be parsed at all, so nothing was sent anywhere.
  final bool malformedUrl;

  /// The address carried `user:password@`, and Garfin dropped it.
  ///
  /// Surfaced rather than silently discarded: a parent who typed proxy
  /// credentials deliberately deserves to be told they are gone, and why, on
  /// the screen where they typed them.
  final bool credentialsDropped;

  SignInState copyWith({
    String? serverUrl,
    bool? quickConnectAvailable,
    bool? busy,
    JellyfinException? error,
    bool? malformedUrl,
    bool? credentialsDropped,
    bool clearError = false,
    bool clearServerUrl = false,
  }) =>
      SignInState(
        serverUrl: clearServerUrl ? null : (serverUrl ?? this.serverUrl),
        quickConnectAvailable:
            quickConnectAvailable ?? this.quickConnectAvailable,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        malformedUrl: malformedUrl ?? this.malformedUrl,
        credentialsDropped: credentialsDropped ?? this.credentialsDropped,
      );
}

final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);

/// Drives the address step and the password fallback.
///
/// Quick Connect has its own controller because a pairing has a lifetime of its
/// own — see [QuickConnectController].
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  /// The address to prefill. Remembered across sign-outs; it identifies the
  /// household's server, not the session.
  String? get rememberedServerUrl =>
      ref.read(authRepositoryProvider).rememberedServerUrl;

  /// Accepts an address and asks the server whether Quick Connect is on.
  ///
  /// Doubles as the reachability check: `GET /QuickConnect/Enabled` is
  /// anonymous and needed anyway, so a wrong address fails here — on the screen
  /// where the address is — instead of inside a sign-in attempt.
  Future<void> useServer(String input) async {
    // Read before normalising, because normalising is what removes them.
    final droppedCredentials = addressCarriesCredentials(input);
    final normalized = normalizeServerUrl(input);
    if (normalized == null) {
      state = state.copyWith(
        malformedUrl: true,
        credentialsDropped: droppedCredentials,
        clearError: true,
      );
      return;
    }

    state = state.copyWith(
      busy: true,
      malformedUrl: false,
      credentialsDropped: droppedCredentials,
      clearError: true,
    );
    try {
      final enabled =
          await ref.read(authRepositoryProvider).quickConnectEnabled(normalized);
      if (!ref.mounted) return;
      state = state.copyWith(
        serverUrl: normalized,
        quickConnectAvailable: enabled,
        busy: false,
      );
    } on JellyfinException catch (error) {
      if (!ref.mounted) return;
      if (error.kind == JellyfinErrorKind.notFound) {
        // Reached a Jellyfin that predates the Quick Connect endpoints. That is
        // a server without Quick Connect, not an unreachable one — go on to the
        // password tab rather than refusing an address that works.
        state = state.copyWith(
          serverUrl: normalized,
          quickConnectAvailable: false,
          busy: false,
        );
        return;
      }
      state = state.copyWith(
        busy: false,
        error: JellyfinException(
          error.kind,
          message: error.message,
          detail: normalized,
        ),
      );
    }
  }

  /// Back to the address step.
  void changeServer() {
    state = const SignInState();
  }

  Future<void> signInWithPassword({
    required String username,
    required String password,
  }) async {
    final serverUrl = state.serverUrl;
    if (serverUrl == null) return;

    state = state.copyWith(busy: true, clearError: true);
    try {
      final session =
          await ref.read(authRepositoryProvider).signInWithPassword(
                serverUrl: serverUrl,
                username: username,
                password: password,
              );
      if (!ref.mounted) return;
      state = state.copyWith(busy: false);
      ref.read(authControllerProvider.notifier).adopt(session);
    } on JellyfinException catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, error: error);
    }
  }
}

/// A Quick Connect pairing in progress.
sealed class QuickConnectState {
  const QuickConnectState();
}

class QuickConnectIdle extends QuickConnectState {
  const QuickConnectIdle();
}

/// `Initiate` is in flight; there is no code to show yet.
class QuickConnectStarting extends QuickConnectState {
  const QuickConnectStarting();
}

/// The code is on screen and Garfin is polling.
class QuickConnectWaiting extends QuickConnectState {
  const QuickConnectWaiting(this.code);

  final String code;
}

class QuickConnectFailed extends QuickConnectState {
  const QuickConnectFailed(this.error);

  final JellyfinException error;
}

class QuickConnectSucceeded extends QuickConnectState {
  const QuickConnectSucceeded();
}

final quickConnectControllerProvider =
    NotifierProvider.autoDispose<QuickConnectController, QuickConnectState>(
  QuickConnectController.new,
);

/// Runs one pairing at a time and cleans it up.
///
/// The session holds the `Secret`, so every exit from this controller has to
/// end in [QuickConnectSession.dispose] — including the screen being popped,
/// which is what `ref.onDispose` covers.
class QuickConnectController extends Notifier<QuickConnectState> {
  QuickConnectSession? _session;

  @override
  QuickConnectState build() {
    ref.onDispose(_stop);
    return const QuickConnectIdle();
  }

  Future<void> start(String serverUrl) async {
    _stop();

    final repository = ref.read(authRepositoryProvider);
    final session = repository.beginQuickConnect(serverUrl);
    _session = session;
    state = const QuickConnectStarting();

    try {
      final result = await session.run(
        onCode: (code) {
          if (ref.mounted && identical(_session, session)) {
            state = QuickConnectWaiting(code);
          }
        },
      );
      final authSession = await repository.completeSignIn(
        serverUrl: serverUrl,
        result: result,
      );
      if (!ref.mounted || !identical(_session, session)) return;
      state = const QuickConnectSucceeded();
      ref.read(authControllerProvider.notifier).adopt(authSession);
    } on JellyfinException catch (error) {
      if (!ref.mounted || !identical(_session, session)) return;
      state = QuickConnectFailed(error);
    } finally {
      session.dispose();
      if (identical(_session, session)) _session = null;
    }
  }

  /// Shortens the current backoff. Called when the app is resumed — the user
  /// has probably just come back from approving the code.
  void poke() => _session?.poke();

  void _stop() {
    _session?.dispose();
    _session = null;
  }
}
