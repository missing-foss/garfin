// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:garfin/main.dart';

void main() {
  testWidgets('app boots and applies the brand theme', (tester) async {
    await tester.pumpWidget(const GarfinApp());
    // DynamicColorBuilder resolves its platform query asynchronously.
    await tester.pumpAndSettle();

    expect(find.text('Garfin'), findsOneWidget);
  });
}
