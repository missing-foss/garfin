// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'library_item.dart';

/// One `/Items` response: the slice, and the size of the whole.
class LibraryPage {
  const LibraryPage({
    required this.items,
    required this.totalRecordCount,
    required this.startIndex,
  });

  const LibraryPage.empty()
      : items = const [],
        totalRecordCount = 0,
        startIndex = 0;

  final List<LibraryItem> items;

  /// The server's count of everything matching the query, not just this slice.
  final int totalRecordCount;

  final int startIndex;

  /// Whether anything remains after this slice.
  bool get hasMore => startIndex + items.length < totalRecordCount;

  /// Where the next request should start.
  int get nextStartIndex => startIndex + items.length;
}
