// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

/// How many calls a batch may have in flight at once.
///
/// `docs/JELLYFIN-API.md`: "keep a small concurrency limit (3–4) so a big
/// collection doesn't flood the server". Measured on 10.11.11, five member
/// writes at four-at-a-time completed in 0.2s, so the limit costs nothing worth
/// having and a fifty-film set stays four requests wide instead of fifty.
const int batchConcurrency = 4;

/// Runs [task] over [items], at most [limit] at a time, in order.
///
/// One result per item, in the order the items came in.
///
/// **A task that throws takes the whole call with it** — the error surfaces and
/// the results are lost. That is the right answer for a read, where a failed
/// batch is simply a failed read. It is the wrong answer for the write path,
/// where "one member failed" must not discard the knowledge of which others
/// succeeded, so the write path hands in a task that catches and reports its
/// own outcome. Ground rule 5: fix forward, and to fix forward you first have
/// to know what happened.
Future<List<R>> mapBounded<T, R>(
  List<T> items,
  Future<R> Function(T item) task, {
  int limit = batchConcurrency,
}) async {
  if (items.isEmpty) return const [];

  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await task(items[index]);
    }
  }

  final workers = <Future<void>>[
    for (var i = 0; i < limit && i < items.length; i++) worker(),
  ];
  await Future.wait(workers);

  return results.cast<R>().toList(growable: false);
}
