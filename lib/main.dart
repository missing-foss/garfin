// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/gen/app_localizations.dart';
import 'logging.dart';
import 'providers/app_providers.dart';
import 'repositories/device_identity.dart';
import 'screens/app_root.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Quieter in release: Garfin holds a Jellyfin admin token, and the less that
  // reaches a device log the smaller the surface. `redactSecrets` scrubs what
  // does get through either way.
  configureLogging(level: kReleaseMode ? Level.WARNING : Level.INFO);

  // Both need async setup before the first frame, so they are resolved here and
  // injected. See the note on `sharedPreferencesProvider` for why those
  // providers throw rather than building an instance of their own.
  final prefs = await SharedPreferences.getInstance();
  final identity = await DeviceIdentity.load(prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
      ],
      child: const GarfinApp(),
    ),
  );
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
          home: const AppRoot(),
        );
      },
    );
  }
}
