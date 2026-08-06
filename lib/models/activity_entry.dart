// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One thing the parent did, as Garfin recorded it.
///
/// **One entry per action, not per write.** Handing over a twelve-film
/// collection is one thing a parent did; twelve rows would bury it and make the
/// screen useless exactly when it matters most.
///
/// This is Garfin's own record. Measured for #57: Jellyfin's
/// `/System/ActivityLog/Entries` does not gain an entry when an item's metadata
/// is written, so there is nothing on the server to read this back from — and
/// therefore nothing here knows about a tag added from the web admin or from a
/// second phone.
class ActivityEntry {
  const ActivityEntry({
    required this.itemId,
    required this.itemName,
    required this.childId,
    required this.childName,
    required this.label,
    required this.gaveAccess,
    required this.at,
    this.collectionSize,
  });

  final String itemId;
  final String itemName;
  final String childId;
  final String childName;

  /// The label that changed, in the casing that was written.
  final String label;

  /// Whether the child gained access, **not** whether a tag was added.
  ///
  /// Ground rule 3: for a block-list child those are opposites, and this screen
  /// speaks the parent's language — "Handed to Sam" — rather than the tag's.
  final bool gaveAccess;

  final DateTime at;

  /// How many titles were inside, when the action was a collection.
  ///
  /// The **membership is deliberately not stored**. Undoing re-resolves it from
  /// the server, because a set can gain or lose films between the write and the
  /// undo, and replaying a captured list is the same mistake as replaying a
  /// captured item body.
  final int? collectionSize;

  bool get isCollection => collectionSize != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'itemId': itemId,
        'itemName': itemName,
        'childId': childId,
        'childName': childName,
        'label': label,
        'gaveAccess': gaveAccess,
        'at': at.toUtc().toIso8601String(),
        if (collectionSize != null) 'collectionSize': collectionSize,
      };

  /// Null when the stored shape cannot be read.
  ///
  /// A log entry is not worth crashing the screen over: an entry written by a
  /// later version, or a half-written value, drops out and the rest of the
  /// history still renders.
  static ActivityEntry? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(readString(json, 'at') ?? '');
    final itemId = readString(json, 'itemId');
    final childId = readString(json, 'childId');
    if (at == null || itemId == null || childId == null) return null;

    return ActivityEntry(
      itemId: itemId,
      itemName: readString(json, 'itemName') ?? '',
      childId: childId,
      childName: readString(json, 'childName') ?? '',
      label: readString(json, 'label') ?? '',
      gaveAccess: readField(json, 'gaveAccess') == true,
      at: at.toLocal(),
      collectionSize: readInt(json, 'collectionSize'),
    );
  }
}
