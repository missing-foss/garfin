// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging.dart';
import '../models/auth_session.dart';
import '../repositories/auth_repository.dart';
import '../repositories/jellyfin_exception.dart';
import 'app_providers.dart';

/// Whether Garfin has a usable session, and how sure it is.
sealed class AuthState {
  const AuthState();
}

/// No session, or one that was just given up.
///
/// [reason] is set when the user was signed out by something other than their
/// own choice — a demoted account, or a token the server no longer honours —
/// so the sign-in screen can say why rather than just reappearing.
class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.reason});

  final JellyfinException? reason;
}

/// A session Garfin is acting on.
///
/// [verified] is false for a session restored from storage that has not yet
/// been confirmed against the server. The app is usable in that state on
/// purpose: a cold start with no network shows the cached account and an
/// [offlineReason], not a blank screen and not a sign-out
/// (`CLAUDE.md` § Definition of done).
class AuthSignedIn extends AuthState {
  const AuthSignedIn({
    required this.session,
    required this.verified,
    this.offlineReason,
    this.justSignedIn = false,
  });

  final AuthSession session;
  final bool verified;

  /// Whether this session was created by someone signing in just now, rather
  /// than restored from storage at launch.
  ///
  /// It decides one thing: whether the unlock question may be asked (#69). A
  /// *restored* session belongs to a phone that has been closed and reopened —
  /// possibly by someone who should not have it — so offering "not now" there
  /// would be offering to skip the gate to whoever is holding the phone. Right
  /// after an interactive sign-in there is no such doubt: they have just proved
  /// they hold the Jellyfin credentials.
  final bool justSignedIn;

  /// Why the session could not be confirmed. Present means "showing what we
  /// already knew"; absent with [verified] true means the server agreed.
  final JellyfinException? offlineReason;

  AuthSignedIn copyWith({
    bool? verified,
    JellyfinException? offlineReason,
    bool clearOfflineReason = false,
  }) =>
      AuthSignedIn(
        session: session,
        verified: verified ?? this.verified,
        offlineReason:
            clearOfflineReason ? null : (offlineReason ?? this.offlineReason),
        // Carried, not reset: `refreshSession` copies the state a moment after
        // sign-in, and dropping this would retract the right to ask the unlock
        // question before it had been asked.
        justSignedIn: justSignedIn,
      );
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Owns the session for the whole app.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    final session = await _repository.restore();
    if (session == null) return const AuthSignedOut();

    // Confirm in the background rather than blocking the first frame on a
    // network round-trip. On a phone that has just been unlocked in another
    // room, that round-trip can be seconds of white screen.
    Future<void>.microtask(refreshSession);

    return AuthSignedIn(session: session, verified: false);
  }

  /// Re-checks the restored session against the server.
  ///
  /// The three outcomes are deliberately different:
  ///
  /// * The account is no longer an administrator, or the token is rejected —
  ///   sign out and say why. Ground rule 7 is about the account in use, not
  ///   only the one that signed in.
  /// * The server cannot be reached — stay signed in, flag it, carry on with
  ///   what is cached.
  /// * It works — clear the flag.
  Future<void> refreshSession() async {
    final current = state.value;
    if (current is! AuthSignedIn) return;

    try {
      await _repository.verify(current.session);
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(verified: true, clearOfflineReason: true),
      );
    } on JellyfinException catch (error) {
      if (!ref.mounted) return;
      switch (error.kind) {
        case JellyfinErrorKind.notAdministrator:
        case JellyfinErrorKind.unauthorized:
          log.info('stored session is no longer usable: ${error.kind.name}');
          await _repository.signOut();
          if (!ref.mounted) return;
          state = AsyncData(AuthSignedOut(reason: error));
        // Garfin's own refusal, from the Quick Connect approval path (#40).
        // A session check cannot produce it; it is listed so this switch stays
        // exhaustive rather than growing a default that would swallow a kind
        // added later.
        case JellyfinErrorKind.unusableUserId:
        case JellyfinErrorKind.unreachable:
        case JellyfinErrorKind.timeout:
        case JellyfinErrorKind.forbidden:
        case JellyfinErrorKind.notFound:
        case JellyfinErrorKind.server:
        case JellyfinErrorKind.quickConnectUnavailable:
        case JellyfinErrorKind.quickConnectExpired:
        case JellyfinErrorKind.cancelled:
          state = AsyncData(current.copyWith(offlineReason: error));
      }
    }
  }

  /// Adopts a session that has already passed the admin check in
  /// [AuthRepository.completeSignIn].
  void adopt(AuthSession session) {
    state = AsyncData(
      AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
  }

  Future<void> signOut() async {
    await _repository.signOut();
    if (!ref.mounted) return;
    state = const AsyncData(AuthSignedOut());
  }
}
