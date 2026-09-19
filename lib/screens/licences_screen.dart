// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../l10n/gen/app_localizations.dart';

/// The packages Garfin chose, with their licences.
///
/// **This groups the display and hides nothing.** Measured on the 0.2.0 release
/// build, the built-in licence page lists **201 packages** — `icu` alone carries
/// 559 licence entries, then `harfbuzz`, `skia`, `angle`, `boringssl`. Almost
/// all of it arrives with the Flutter engine and none of it is a decision
/// anyone made here, so the dozen that were are impossible to find. This screen
/// is that dozen; the full page is still one row below it in About, still
/// generated from what is actually linked, and still the authoritative list.
///
/// **That last claim depends on a registration in `main.dart`, and stopped
/// being free the moment this app gained a dependency Gradle resolves.**
/// `LicenseRegistry` is built from Dart package licences and the engine's
/// vendored `NOTICES`; an Android library is linked into the APK without
/// appearing in either. So "generated from what is actually linked" is true
/// here only because `main.dart` adds the missing entry by hand. Delete that
/// call and this sentence silently becomes false — the page will not complain,
/// it will simply be one licence short of what shipped.
///
/// **Read from the same registry the built-in page reads.** Not from a bundled
/// notices file, which would be a second list that can disagree with the first
/// and go stale. [directDependencies] and [platformDependencies] decide only
/// *which* packages to show — the first a fact `pubspec.yaml` holds and a test
/// keeps honest, the second hand-kept because no file here holds it — and never
/// what licence any of them carries. Naming a licence would mean inferring a
/// legal fact from free text, which is the one thing a screen like this must
/// not do.
class LicencesScreen extends StatelessWidget {
  const LicencesScreen({super.key});

  /// Every licence entry belonging to one of [directDependencies] or
  /// [platformDependencies].
  ///
  /// A package with no entry of its own keeps its row, empty, rather than
  /// being dropped: silently listing fewer dependencies than Garfin has is the
  /// thing this screen exists to stop, and a tidier list is exactly what makes
  /// dropping them tempting.
  ///
  /// **No package reaches that path today** — measured against the release
  /// build's `NOTICES`, all eleven in [directDependencies] have an entry, and
  /// the one in [platformDependencies] has the entry `main.dart` registers. The
  /// one dependency without its own licence, `flutter_localizations`, is
  /// `sdk: flutter` and is excluded from that list before it gets here, so it
  /// is not an example of this case. The empty row is for a package that
  /// arrives without one later; *a package with a licence opens it; one
  /// without does not* is what keeps the branch honest in the meantime.
  static Future<Map<String, List<LicenseEntry>>> _read() async {
    // Both lists, because the APK contains both. `directDependencies` is the
    // pub side, derived from `pubspec.yaml`; `platformDependencies` is what
    // Gradle links in, which `LicenseRegistry` cannot discover and `main.dart`
    // registers by hand.
    const all = [...directDependencies, ...platformDependencies];
    final wanted = all.toSet();
    final found = <String, List<LicenseEntry>>{
      for (final package in all) package: <LicenseEntry>[],
    };
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        if (wanted.contains(package)) found[package]!.add(entry);
      }
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutOurPackages)),
      body: FutureBuilder<Map<String, List<LicenseEntry>>>(
        future: _read(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final packages = data.keys.toList();
          return ListView.builder(
            itemCount: packages.length,
            itemBuilder: (context, i) {
              final package = packages[i];
              final entries = data[package]!;
              return ListTile(
                title: Text(package),
                trailing: const Icon(Icons.chevron_right),
                onTap: entries.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _PackageLicence(
                              package: package,
                              entries: entries,
                            ),
                          ),
                        ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One package's licence text, as the registry gave it.
///
/// Rendered verbatim, paragraph by paragraph, including the indentation the
/// entry asks for. Nothing is summarised: a licence someone reads to check a
/// term is the wrong place to be helpful.
class _PackageLicence extends StatelessWidget {
  const _PackageLicence({required this.package, required this.entries});

  final String package;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphs = [
      for (final entry in entries) ...entry.paragraphs,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(package)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: paragraphs.length,
        itemBuilder: (context, i) {
          final paragraph = paragraphs[i];
          final centered =
              paragraph.indent == LicenseParagraph.centeredIndent;
          return Padding(
            padding: EdgeInsets.only(
              left: centered ? 0 : paragraph.indent * 12.0,
              bottom: 12,
            ),
            child: Text(
              paragraph.text,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.bodySmall,
            ),
          );
        },
      ),
    );
  }
}
