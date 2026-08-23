// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// Reads a field out of a Jellyfin DTO by its documented (PascalCase) name,
/// tolerating the casing the server actually used.
///
/// **Measured on 10.11.11, 2026-08-03.** Jellyfin content-negotiates JSON
/// casing: `Accept: application/json` gets PascalCase, and
/// `application/json; profile="CamelCase"` gets camelCase. Garfin asks for
/// plain `application/json`, so PascalCase is what it should get.
///
/// It does not always. Polling `GET /System/Info/Public` across a container
/// restart returned **camelCase with HTTP 200** for the first second or so,
/// then a 503 loading page, then PascalCase steady state. A parser keyed on
/// exact names would read that early reply as an object with every field
/// missing — which for `AuthenticationResult` means an empty access token and a
/// `Policy` that looks like "not an administrator", i.e. a sign-in refused for
/// the wrong reason on a server that had just rebooted.
///
/// The exact-key path is tried first, so the steady-state case costs one map
/// lookup and this only walks the map when a name is genuinely absent.
Object? readField(Map<String, dynamic> json, String name) {
  if (json.containsKey(name)) return json[name];

  final lower = name.toLowerCase();
  for (final entry in json.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

/// [readField] for a string, with absent and wrong-typed both meaning null.
String? readString(Map<String, dynamic> json, String name) {
  final value = readField(json, name);
  return value is String ? value : null;
}

/// [readField] for a boolean.
///
/// Absent means false everywhere Garfin uses this, and that is the safe
/// direction: `IsAdministrator` missing must not read as "administrator".
bool readBool(Map<String, dynamic> json, String name) =>
    readField(json, name) == true;

/// [readField] for a nested object.
Map<String, dynamic>? readMap(Map<String, dynamic> json, String name) {
  final value = readField(json, name);
  return value is Map<String, dynamic> ? value : null;
}

/// [readField] for an integer, where **absent and null are the same answer**.
///
/// `MaxParentalRating` is the reason this returns `int?` rather than defaulting.
/// Measured on 10.11.11: it is an integer for a capped child and `null` for an
/// uncapped one — and `null` means *no cap*, which is the opposite of the
/// restrictive reading. Defaulting it to `0` would invent the strictest
/// possible cap out of a missing field.
///
/// Tolerates a JSON number arriving as a double, which `dart:convert` does for
/// anything written `7.0`.
int? readInt(Map<String, dynamic> json, String name) {
  final value = readField(json, name);
  if (value is int) return value;
  if (value is double) return value.toInt();
  return null;
}

/// [readField] for a list of strings, absent or wrong-typed meaning empty.
///
/// Empty is the right default here and not a fudge: measured on 10.11.11,
/// `AllowedTags` and `BlockedTags` are **always present as arrays**, empty
/// rather than null, on every user including the administrator. So an absent
/// one is a server that changed, and "no tags" is both the honest reading and
/// the one that leaves a user out of shortlist control rather than inventing
/// one for them.
List<String> readStringList(Map<String, dynamic> json, String name) {
  final value = readField(json, name);
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

/// [readField] for a number that may legitimately have a fraction.
///
/// `AccessSchedules` is why this exists: `StartHour` and `EndHour` are
/// **floats** — measured, `8.5` is 08:30 — and reading them with [readInt]
/// would truncate a parent's half-past to the hour, in the direction of *more*
/// access. An integer arriving where a double is expected is normal in JSON and
/// is accepted; anything else is null rather than a guess.
double? readDouble(Map<String, dynamic> json, String name) {
  final value = readField(json, name);
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return null;
}

