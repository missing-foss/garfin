// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// Identity Garfin presents to Jellyfin in the `Authorization` header, and what
/// the server shows in Dashboard → Devices.
library;

/// The `Client="…"` value. Fixed — this is the product name, not the device.
const appClientName = 'Garfin';

/// The `Version="…"` value.
///
/// Kept in sync with `pubspec.yaml`'s `version:` by `test/app_info_test.dart`,
/// which fails if the two drift. Reading it at runtime instead would mean a
/// `package_info_plus` dependency for one string, and every new dependency
/// costs a licence review (`CONTRIBUTING.md`).
const appVersion = '0.1.0';
