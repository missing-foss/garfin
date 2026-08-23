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
import 'providers/settings_providers.dart';
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

class GarfinApp extends ConsumerWidget {
  const GarfinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Material You where the platform offers it (Android 12+), the brand
        // seed below it — and the brand seed whenever Settings says so, which
        // is the only way to get Garfin's own purple on a phone that has
        // dynamic colour.
        final light = (settings.dynamicColour ? lightDynamic : null) ??
            ColorScheme.fromSeed(seedColor: seedColor);
        final dark = (settings.dynamicColour ? darkDynamic : null) ??
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
          // Dark-first: the app is used in the evening, on a sofa. Settings
          // can move it, and the stored default is dark rather than system.
          themeMode: settings.themeMode,
          // Ground rule 9's gate is inside `AppRoot`, on the signed-in
          // branch, rather than here above everything (#69): before sign-in
          // there is no token, no server address and no children, so what it
          // guarded there was an empty app — and it demanded biometrics from
          // someone who had not yet typed a server address.
          home: const AppRoot(),
        );
      },
    );
  }
}
