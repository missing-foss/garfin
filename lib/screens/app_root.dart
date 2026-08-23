// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../providers/unlock_providers.dart';
import '../widgets/unlock_gate.dart';
import 'home_screen.dart';
import 'sign_in_screen.dart';
import 'unlock_choice_screen.dart';

/// Chooses between sign-in and the app, based on whether there is a session.
///
/// The loading state is the moment between launch and reading storage — long
/// enough to need something on screen, short enough that it should not be a
/// spinner with a message.
///
/// **The unlock gate lives in here rather than above it (#69.)** Ground rule 9
/// is unchanged — Garfin holds an admin token on a phone handed to children —
/// but that premise is not true before sign-in, when there is no token, no
/// server address and no children. Gating there protected an empty app and
/// demanded biometrics from someone who had not yet typed a server address.
/// The premise becomes true the instant a session exists, which is where the
/// gate now starts.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return switch (auth) {
      AsyncData(:final value) => switch (value) {
          AuthSignedOut(:final reason) => SignInScreen(reason: reason),
          AuthSignedIn(justSignedIn: true)
              when !ref.watch(unlockChoiceProvider) =>
            const UnlockChoiceScreen(),
          AuthSignedIn() => UnlockGate(child: HomeScreen(state: value)),
        },
      // Reading the token store is local work that does not fail in practice,
      // but if it ever does the honest place to land is the sign-in screen —
      // not a dead end, and not a session Garfin cannot prove it has.
      AsyncError() => const SignInScreen(),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
