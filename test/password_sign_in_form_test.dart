// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/widgets/password_sign_in_form.dart';
import 'package:material_ui/material_ui.dart';

/// The eye button on the password field says what it does, to sight and to a
/// screen reader, and says the opposite once it has done it.
void main() {
  Future<void> pump(WidgetTester tester, Locale locale) => tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PasswordSignInForm(busy: false, onSubmit: (_, _) {}),
          ),
        ),
      );

  TextField passwordField(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).firstWhere((f) => f.obscureText || f.decoration?.suffixIcon != null);

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('in ${locale.toLanguageTag()}, the eye button is labelled for what it will do', (tester) async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final handle = tester.ensureSemantics();
      await pump(tester, locale);

      expect(passwordField(tester).obscureText, isTrue);
      expect(find.byTooltip(l10n.passwordShowTooltip), findsOneWidget);
      // A screen reader announces a tooltip as part of the button, which is the
      // whole point: without one it says "button" and nothing more.
      expect(tester.getSemantics(find.byTooltip(l10n.passwordShowTooltip)),
          isSemantics(tooltip: l10n.passwordShowTooltip, isButton: true));

      await tester.tap(find.byTooltip(l10n.passwordShowTooltip));
      await tester.pumpAndSettle();

      expect(passwordField(tester).obscureText, isFalse);
      expect(find.byTooltip(l10n.passwordHideTooltip), findsOneWidget);
      expect(find.byTooltip(l10n.passwordShowTooltip), findsNothing);
      handle.dispose();
    });
  }
}
