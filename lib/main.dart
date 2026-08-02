// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/gen/app_localizations.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: GarfinApp()));
}

class GarfinApp extends StatelessWidget {
  const GarfinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Material You where the platform offers it (Android 12+), the brand seed below it.
        final light = lightDynamic ?? ColorScheme.fromSeed(seedColor: seedColor);
        final dark = darkDynamic ??
            ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);

        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: garfinTheme(light),
          darkTheme: garfinTheme(dark),
          // Dark-first: the app is used in the evening, on a sofa.
          themeMode: ThemeMode.dark,
          home: const _NotBuiltYet(),
        );
      },
    );
  }
}

/// Placeholder until the sign-in screen lands. Replace, do not build on.
class _NotBuiltYet extends StatelessWidget {
  const _NotBuiltYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l10n.appTitle, style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                l10n.notBuiltYetBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
