// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/library_providers.dart';

/// Finding one film by name (#73).
///
/// The grid is built from the **administrator's** view on purpose — that is
/// what makes "not given yet" answerable — which also means it is as long as
/// the library. Type, genre and decade narrow by category; none of them narrows
/// to *the one they asked for at dinner*.
///
/// **The server does the matching.** `searchTerm` on the same `/Items` call as
/// the other filters, never a filter applied to a page after it arrives: the
/// match is usually not in the first 24 rows, so filtering client-side would
/// either walk the library a page at a time or report "nothing found" for a
/// film that exists. `library_repository.dart` already carries that
/// client-side-window machinery for hide-shared and it is exactly what this
/// must not use.
class LibrarySearchField extends ConsumerStatefulWidget {
  const LibrarySearchField({super.key});

  /// Long enough that typing a title is one request rather than one per letter,
  /// short enough not to feel like lag. Each keystroke otherwise costs a
  /// server-side library query — the expensive kind, measured in #68 at up to
  /// 7.6 seconds on a large library.
  ///
  /// Public because the test waits exactly this long: a test with its own
  /// hardcoded duration passes for a while and then fails mysteriously the day
  /// someone tunes this.
  static const debounce = Duration(milliseconds: 350);

  @override
  ConsumerState<LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends ConsumerState<LibrarySearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Survives the widget being rebuilt or scrolled out of the row: the filter
    // is the source of truth, not this field.
    _controller.text = ref.read(libraryFiltersProvider).searchTerm ?? '';
  }

  @override
  void dispose() {
    // Without this a pending timer fires into a disposed ref — the standing
    // trap in this repo's widget tests, and a real crash on a fast back-tap.
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(LibrarySearchField.debounce, () {
      if (!mounted) return;
      ref.read(libraryFiltersProvider.notifier).setSearch(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(libraryFiltersProvider.notifier).setSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasText = _controller.text.trim().isNotEmpty;

    return SizedBox(
      width: 220,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.librarySearchHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: l10n.librarySearchClear,
                  onPressed: _clear,
                )
              : null,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onChanged: (value) {
          // A rebuild for the clear button, which depends on emptiness rather
          // than on the debounced value.
          setState(() {});
          _onChanged(value);
        },
        // Enter applies immediately: waiting out a debounce after a deliberate
        // submit reads as the app ignoring you.
        onSubmitted: (value) {
          _debounce?.cancel();
          ref.read(libraryFiltersProvider.notifier).setSearch(value);
        },
      ),
    );
  }
}
