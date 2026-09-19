// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/library_filters.dart';
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
  /// server-side library query — the expensive kind, measured at up to
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

  /// The placeholder for the scope in force.
  ///
  /// Three strings rather than one neutral "Search", because the field is the
  /// only place the scope is visible once the menu closes, and a parent who
  /// typed a name and got nothing needs to see *what was searched* to know the
  /// menu is the answer.
  String _hint(AppLocalizations l10n, SearchScope scope) => switch (scope) {
    SearchScope.title => l10n.librarySearchHint,
    SearchScope.castAndCrew => l10n.librarySearchHintCastAndCrew,
    SearchScope.studio => l10n.librarySearchHintStudio,
  };

  String _scopeLabel(AppLocalizations l10n, SearchScope scope) =>
      switch (scope) {
        SearchScope.title => l10n.librarySearchScopeTitle,
        SearchScope.castAndCrew => l10n.librarySearchScopeCastAndCrew,
        SearchScope.studio => l10n.librarySearchScopeStudio,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasText = _controller.text.trim().isNotEmpty;
    final scope = ref.watch(
      libraryFiltersProvider.select((filters) => filters.searchScope),
    );

    // No width of its own: the filter bar gives it everything the tune button
    // does not take. It was a fixed 300dp when a scrolling row of filter chips
    // followed it.
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: _hint(l10n, scope),
        // The scope sits *inside* the field rather than beside it, so the
        // control and the thing it governs cannot be read apart. It replaces
        // the magnifying glass: an icon that says nothing, where a word says
        // which of three questions is about to be asked.
        prefixIcon: PopupMenuButton<SearchScope>(
          tooltip: l10n.librarySearchScope,
          initialValue: scope,
          onSelected: ref.read(libraryFiltersProvider.notifier).setScope,
          itemBuilder: (context) => [
            for (final option in SearchScope.values)
              PopupMenuItem<SearchScope>(
                value: option,
                child: Text(_scopeLabel(l10n, option)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _scopeLabel(l10n, scope),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, maxWidth: 132),
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
    );
  }
}
