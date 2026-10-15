// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/widgets/error_notice.dart';

/// Every way a request can fail is told to the user in its own sentence, in
/// every language Garfin ships, with the server's name or address slotted in
/// where the sentence has room for it.
void main() {
  const detail = 'jellyfin.example';

  for (final locale in AppLocalizations.supportedLocales) {
    group('in ${locale.toLanguageTag()}', () {
      late AppLocalizations l10n;
      setUpAll(() async => l10n = await AppLocalizations.delegate.load(locale));

      test('no two kinds of failure share a sentence', () {
        final byText = <String, List<JellyfinErrorKind>>{};
        for (final kind in JellyfinErrorKind.values) {
          final text = jellyfinErrorText(l10n, JellyfinException(kind, detail: detail));
          expect(text.trim(), isNotEmpty, reason: '$kind');
          byText.putIfAbsent(text, () => []).add(kind);
        }
        final shared = byText.values.where((kinds) => kinds.length > 1).toList();
        expect(shared, isEmpty, reason: 'one sentence for several kinds');
      });

      test('the address goes into the sentences that name one', () {
        for (final kind in [
          JellyfinErrorKind.unreachable,
          JellyfinErrorKind.moved,
          JellyfinErrorKind.notAdministrator,
        ]) {
          expect(jellyfinErrorText(l10n, JellyfinException(kind, detail: detail)),
              contains(detail),
              reason: '$kind');
        }
      });

      test('a move with no new address says so without a hole', () {
        final withAddress = jellyfinErrorText(
            l10n, const JellyfinException(JellyfinErrorKind.moved, detail: detail));
        final without =
            jellyfinErrorText(l10n, const JellyfinException(JellyfinErrorKind.moved));
        expect(without, isNot(contains('null')));
        expect(without, isNot(withAddress.replaceAll(detail, '')));
      });
    });
  }

  group('ErrorNotice', () {
    Future<void> pump(WidgetTester tester, {String? diagnostic}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ErrorNotice(message: 'Could not reach the server', diagnostic: diagnostic),
            ),
          ),
        );

    testWidgets('shows the cause underneath, selectable to copy', (tester) async {
      await pump(tester, diagnostic: 'SocketException: Connection refused (errno = 111)');
      expect(find.text('Could not reach the server'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'SocketException: Connection refused (errno = 111)'),
          findsOneWidget);
    });

    testWidgets('with no cause, or an empty one, shows only the sentence', (tester) async {
      for (final diagnostic in [null, '']) {
        await pump(tester, diagnostic: diagnostic);
        expect(find.byType(SelectableText), findsNothing, reason: '$diagnostic');
        expect(find.text('Could not reach the server'), findsOneWidget);
      }
    });
  });
}
