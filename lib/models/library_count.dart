// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'jellyfin_user.dart';

/// What the Library's result line is counting.
///
/// Three different sentences, because a child's shortlist has two opposite
/// verbs and one shape Garfin refuses to read (#81, ground rule 3).
enum LibraryCountKind {
  /// The library, as the administrator sees it under the active filters. Used
  /// with no child selected, and as the fallback whenever a per-child number
  /// cannot be had — a conflicting account, or a count that has not arrived.
  everything,

  /// An allow-list child: what has **not been handed over**. Never "what they
  /// cannot see" — the rating cap silently overrides tags, so the two are
  /// different numbers and only the server knows the second (ground rule 4).
  notYetGiven,

  /// A block-list child: what the label is **taking away** from them. The same
  /// query, the opposite verb, per ground rule 3's "detect the mode and invert
  /// every action".
  withheld,
}

/// The result line's number and what it means.
class LibraryCount {
  const LibraryCount(this.kind, this.count);

  final LibraryCountKind kind;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is LibraryCount && other.kind == kind && other.count == count;

  @override
  int get hashCode => Object.hash(kind, count);

  @override
  String toString() => 'LibraryCount($kind, $count)';
}

/// The result line for [child], from two **server** counts.
///
/// [total] is the grid's own `TotalRecordCount` — everything the administrator
/// can see under the active filters — and [tagged] is how many of those carry
/// the child's shortlist labels. Both come back from `/Items`; nothing here
/// counts anything itself.
///
/// **This is a subtraction, not a visibility computation.** `/Items` has no
/// `excludeTags` — 86 parameters and not one of them — so "not handed over
/// yet" cannot be asked for directly and has to be derived. What it derives is
/// a fact about *labels*, which is the same thing the tiles say. What a child
/// can actually watch stays the server's answer, and ground rule 4 keeps this
/// out of it.
///
/// **Both counts must carry the same filters**, or this subtracts one
/// population from another and returns a number that looks entirely
/// reasonable. `JellyfinApi.taggedItemCount` takes the filter set for exactly
/// that reason.
///
/// Clamped at zero rather than allowed to go negative: the two counts are two
/// requests, so a library edited between them can answer with a larger tagged
/// count than total. A "-3" on screen is a bug report from a parent; a 0 is a
/// grid that has nothing left in it, which is also what it will look like.
LibraryCount libraryCountFor({
  required int total,
  required int tagged,
  required JellyfinUser? child,
}) {
  if (child == null) return LibraryCount(LibraryCountKind.everything, total);

  return switch (child.policy.shortlistMode) {
    ShortlistMode.allow =>
      LibraryCount(LibraryCountKind.notYetGiven, (total - tagged).clamp(0, total)),
    ShortlistMode.block => LibraryCount(LibraryCountKind.withheld, tagged),
    // Ground rule 3: with both lists live there is no correct verb, so there
    // is no correct per-child number either. The library's own count is still
    // true, and it is a statement about the library rather than about them.
    ShortlistMode.conflicting ||
    ShortlistMode.none =>
      LibraryCount(LibraryCountKind.everything, total),
  };
}
