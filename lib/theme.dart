// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// The brand seed. Every colour in the app derives from this or from Material You.
/// See BRANDING.md — do not introduce colours outside the generated scheme.
const seedColor = Color(0xFF7C5CD6);

/// Fredoka for headings, titles, numbers and buttons; Nunito for body and UI.
/// RobotoMono is applied per-widget for tag strings, not through the text theme.
ThemeData garfinTheme(ColorScheme scheme) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final t = base.textTheme;

  TextStyle? display(TextStyle? s) => s?.copyWith(fontFamily: 'Fredoka', fontWeight: FontWeight.w600);
  TextStyle? body(TextStyle? s) => s?.copyWith(fontFamily: 'Nunito');

  return base.copyWith(
    textTheme: t.copyWith(
      displayLarge: display(t.displayLarge),
      displayMedium: display(t.displayMedium),
      displaySmall: display(t.displaySmall),
      headlineLarge: display(t.headlineLarge),
      headlineMedium: display(t.headlineMedium),
      headlineSmall: display(t.headlineSmall),
      titleLarge: display(t.titleLarge),
      titleMedium: display(t.titleMedium),
      titleSmall: display(t.titleSmall),
      labelLarge: display(t.labelLarge),
      labelMedium: display(t.labelMedium),
      labelSmall: display(t.labelSmall),
      bodyLarge: body(t.bodyLarge),
      bodyMedium: body(t.bodyMedium),
      bodySmall: body(t.bodySmall),
    ),
  );
}

/// Tag strings and anything else that must not reflow between renders.
const tagTextStyle = TextStyle(fontFamily: 'RobotoMono');
