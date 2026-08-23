// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/bounded_batch.dart';

/// The concurrency limit `docs/JELLYFIN-API.md` asks for: "3–4, so a big
/// collection doesn't flood the server".
///
/// A limit that is stated and not enforced is the same as no limit, and the
/// difference only shows up on somebody's fifty-film set.
void main() {
  test('never more than the limit are in flight at once', () async {
    var running = 0;
    var peak = 0;
    final gates = <Completer<void>>[];

    final batch = mapBounded<int, int>(
      List.generate(20, (i) => i),
      (i) async {
        running++;
        peak = running > peak ? running : peak;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        running--;
        return i;
      },
      limit: 4,
    );

    // Let everything that can start, start; then release one at a time.
    await Future<void>.delayed(Duration.zero);
    while (gates.any((g) => !g.isCompleted)) {
      gates.firstWhere((g) => !g.isCompleted).complete();
      await Future<void>.delayed(Duration.zero);
    }

    expect(await batch, List.generate(20, (i) => i));
    expect(peak, 4);
  });

  test('results come back in the order the items went in', () async {
    // The batch reports "film-2 failed", so a result that drifted from its item
    // would name the wrong one.
    final results = await mapBounded<int, String>(
      List.generate(9, (i) => i),
      // Later items finish first, which is what shuffles an unordered
      // implementation.
      (i) async {
        await Future<void>.delayed(Duration(milliseconds: (9 - i) * 2));
        return 'item-$i';
      },
      limit: 4,
    );

    expect(results, List.generate(9, (i) => 'item-$i'));
  });

  test('an empty batch does nothing at all', () async {
    var called = false;
    final results = await mapBounded<int, int>([], (i) async {
      called = true;
      return i;
    });
    expect(results, isEmpty);
    expect(called, isFalse);
  });

  test('a batch smaller than the limit still runs every item', () async {
    final results = await mapBounded<int, int>(
      [1, 2],
      (i) async => i * 10,
      limit: 4,
    );
    expect(results, <int>[10, 20]);
  });
}
