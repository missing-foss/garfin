// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import 'home_screen.dart';
import 'sign_in_screen.dart';

/// Chooses between sign-in and the app, based on whether there is a session.
///
/// The loading state is the moment between launch and reading storage — long
/// enough to need something on screen, short enough that it should not be a
/// spinner with a message.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return switch (auth) {
      AsyncData(:final value) => switch (value) {
          AuthSignedOut(:final reason) => SignInScreen(reason: reason),
          AuthSignedIn() => HomeScreen(state: value),
        },
      // Reading the token store is local work that does not fail in practice,
      // but if it ever does the honest place to land is the sign-in screen —
      // not a dead end, and not a session Garfin cannot prove it has.
      AsyncError() => const SignInScreen(),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
