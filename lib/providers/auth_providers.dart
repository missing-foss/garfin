// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

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
/// (`docs/ENGINEERING.md` § Definition of done).
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

  /// A check is in flight. A burst of 401s — every screen's request failing at
  /// once after a revoke — asks for one check, not one each; and the check's
  /// own request reports to the same relay, which must not start another.
  bool _refreshing = false;

  /// Signing out is under way. The revoke is an authenticated call like any
  /// other and reports to the same relay; its answer — or a screen's request
  /// still landing — must not start a check of a session being given up.
  bool _signingOut = false;

  /// When a check last finished, for [_noteReachable]'s throttle.
  DateTime? _lastChecked;

  /// The least time between two checks that a *successful* call asks for.
  ///
  /// Only that path is throttled. A success is every call the app makes, and
  /// if the check itself keeps failing while other calls succeed, each page of
  /// the grid would otherwise ask for another. A 401 is not throttled — a
  /// device revoked a minute after launch must not wait out an interval — and
  /// a burst of them is one check already, through [_refreshing]. Resume and
  /// *Try again* are a person asking and are never throttled.
  static const reachableInterval = Duration(seconds: 30);

  @override
  Future<AuthState> build() async {
    // Every authenticated call reports here from now on, rather than the
    // session being checked once at launch and never again.
    final signals = ref.read(sessionSignalsProvider)
      ..attach(
        onUnauthorized: () => unawaited(refreshSession()),
        onReachable: _noteReachable,
      );
    ref.onDispose(signals.detach);

    final session = await _repository.restore();
    if (session == null) return const AuthSignedOut();

    // Confirm in the background rather than blocking the first frame on a
    // network round-trip. On a phone that has just been unlocked in another
    // room, that round-trip can be seconds of white screen.
    unawaited(Future<void>.microtask(refreshSession));

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
  ///
  /// Asked at launch, on every resume, from every *Try again*, after any
  /// authenticated call is refused with 401, and after the first call that
  /// succeeds while the session is unconfirmed. A 401 is not taken at its word:
  /// this check is what decides, so one endpoint's refusal cannot sign the
  /// parent out of a session the server still honours.
  Future<void> refreshSession() async {
    final current = state.value;
    if (current is! AuthSignedIn) return;
    if (_refreshing || _signingOut) return;
    _refreshing = true;

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
          // A demoted account's token still works, so it is revoked like any
          // other. A refused one has nothing left to revoke.
          await _repository.signOut(
            revoke: error.kind != JellyfinErrorKind.unauthorized,
          );
          if (!ref.mounted) return;
          state = AsyncData(AuthSignedOut(reason: error));
        // Garfin's own refusal, from the Quick Connect approval path (#40).
        // A session check cannot produce it; it is listed so this switch stays
        // exhaustive rather than growing a default that would swallow a kind
        // added later.
        case JellyfinErrorKind.unusableUserId:
        case JellyfinErrorKind.unreachable:
        case JellyfinErrorKind.timeout:
        // The server answered from another address. Not a refusal of the
        // session, so not a sign-out: stay, and say so.
        case JellyfinErrorKind.moved:
        // Not a refusal of the session either: the server is there, behind a
        // certificate this phone does not trust. Stay, and say so.
        case JellyfinErrorKind.untrustedCertificate:
        case JellyfinErrorKind.forbidden:
        case JellyfinErrorKind.notFound:
        case JellyfinErrorKind.server:
        case JellyfinErrorKind.quickConnectUnavailable:
        case JellyfinErrorKind.quickConnectExpired:
        case JellyfinErrorKind.cancelled:
          state = AsyncData(current.copyWith(offlineReason: error));
      }
    } finally {
      _refreshing = false;
      _lastChecked = DateTime.now();
    }
  }



  /// A call went through, so the server is there: the banner saying it is not
  /// comes down now, on the first call that proves otherwise.
  ///
  /// And if the session is still unconfirmed — the launch check never reached
  /// the server — it is confirmed too, because that check is also the
  /// administrator check (rule 7), and a session restored offline has not had
  /// it yet. That part is throttled; the banner is not.
  void _noteReachable() {
    final current = state.value;
    if (current is! AuthSignedIn || _signingOut) return;
    if (current.offlineReason != null) {
      state = AsyncData(current.copyWith(clearOfflineReason: true));
    }
    if (current.verified) return;
    final last = _lastChecked;
    if (last != null && DateTime.now().difference(last) < reachableInterval) {
      return;
    }
    unawaited(refreshSession());
  }

  /// Adopts a session that has already passed the admin check in
  /// [AuthRepository.completeSignIn].
  void adopt(AuthSession session) {
    state = AsyncData(
      AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
  }

  /// The moment has passed: this session is no longer *newly* interactive.
  ///
  /// Called when Garfin is backgrounded while the unlock question is still on
  /// screen (#72's review). Provenance was the only thing gating that
  /// question, and provenance does not expire on its own — so sign in, walk
  /// away, and whoever picks the phone up next is still being offered "not
  /// now". The offer is exactly what the gate exists to deny them.
  ///
  /// Dropping the flag routes the next frame through the gated branch, so the
  /// question is simply not asked again this run and the lock screen stands in
  /// front of the app. Nothing is recorded: `choiceRecorded` stays false, so
  /// the next interactive sign-in asks properly.
  void noteNoLongerFresh() {
    final current = state.value;
    if (current is! AuthSignedIn || !current.justSignedIn) return;
    state = AsyncData(
      AuthSignedIn(
        session: current.session,
        verified: current.verified,
        offlineReason: current.offlineReason,
      ),
    );
  }

  /// The parent's own sign-out, which revokes the token on the server first.
  Future<void> signOut() async {
    _signingOut = true;
    try {
      await _repository.signOut();
      if (!ref.mounted) return;
      state = const AsyncData(AuthSignedOut());
    } finally {
      _signingOut = false;
    }
  }
}
