// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// Whether [version] — Jellyfin's `Version`, as `/System/Info/Public` gives it
/// — is one Garfin has been measured against.
///
/// Every measurement in the code and the docs is from 10.11.11, 12.0.0 or
/// 12.1.x; 10.10 is mentioned nowhere. Nothing refuses another version — it
/// may well work — but a report from one should say so up front, and this is
/// how it does: a line in the log at sign-in.
///
/// An unreadable version is not "untested": it is unknown, and says nothing.
bool? isTestedServerVersion(String? version) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version?.trim() ?? '');
  if (match == null) return null;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return (major == 10 && minor == 11) || major == 12;
}
