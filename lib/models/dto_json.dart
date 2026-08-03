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
