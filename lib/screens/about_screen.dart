// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../providers/update_providers.dart';
import '../repositories/update_repository.dart';

/// What Garfin is, who made it, and where to get it (#66).
///
/// A screen rather than the four tiles it replaces at the bottom of Settings,
/// on the trobar-android model: the mark, the wordmark, the version, then the
/// things a person actually came here for — an update check, four links, and
/// the licences.
///
/// **The links open.** Garfin used to *show* the source address as text, on the
/// reasoning that launching a browser meant another dependency and another
/// licence review for one URL. That reasoning was sound and the conclusion aged
/// badly: a URL you cannot tap on a phone is close to no link at all. The
/// reversal, and `url_launcher`'s licence, are recorded in `docs/DECISIONS.md`.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  bool _checking = false;
  UpdateCheck? _result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 24),
          // The mark is a bundled asset rather than an icon font or an SVG
          // package: `brand/make-app-assets.sh` renders it at 1x/2x/3x from the
          // same SVG the launcher icon comes from, so the picture has one
          // source and no runtime renderer.
          Center(
            child: Image.asset(
              'assets/brand/garfin-mark.png',
              width: 84,
              height: 84,
              // A missing asset otherwise paints a grey box that reads as a
              // loading state on a screen with nothing to load.
              semanticLabel: appClientName,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              // The product name, not a translatable string — and a constant
              // rather than a literal, which `dev/verify.sh` requires.
              appClientName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              l10n.settingsVersion(appVersion),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: _checking ? null : _checkForUpdates,
              icon: _checking
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.update),
              label: Text(l10n.aboutCheckUpdates),
            ),
          ),
          if (_result case final result?) _UpdateResult(result: result),
          const SizedBox(height: 8),
          const Divider(),
          _SectionHeading(l10n.aboutSectionLinks),
          _LinkTile(
            icon: Icons.menu_book_outlined,
            label: l10n.aboutDocs,
            url: '$sourceUrl/tree/main/docs',
          ),
          _LinkTile(
            icon: Icons.code,
            label: l10n.settingsSource,
            url: sourceUrl,
          ),
          _LinkTile(
            icon: Icons.bug_report_outlined,
            label: l10n.aboutIssues,
            url: '$sourceUrl/issues',
          ),
          _LinkTile(
            icon: Icons.download_outlined,
            label: l10n.aboutReleases,
            url: '$sourceUrl/releases',
          ),
          const Divider(),
          _SectionHeading(l10n.aboutSectionLicences),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l10n.settingsLicence,
                style: theme.textTheme.bodyMedium),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.settingsLicences),
            trailing: const Icon(Icons.chevron_right),
            // Flutter's own licence page, which already knows every package
            // compiled in. Rendering a bundled THIRD_PARTY_NOTICES.md instead
            // would mean shipping a second list that can disagree with the
            // first, and the built-in one cannot go stale.
            onTap: () => showLicensePage(
              context: context,
              applicationName: appClientName,
              applicationVersion: appVersion,
              applicationLegalese: l10n.settingsLicence,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.settingsNotAffiliated,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// One call, on a press, and never anywhere else.
  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await ref.read(updateRepositoryProvider).check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// What the check said, in place, rather than a snackbar that slides away.
///
/// A result that disappears after four seconds is the wrong shape for a screen
/// someone opened *in order to* read something, and "is there a new version"
/// deserves to stay on screen while they decide what to do about it.
class _UpdateResult extends StatelessWidget {
  const _UpdateResult({required this.result});

  final UpdateCheck result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final text = switch (result.outcome) {
      UpdateOutcome.available => l10n.aboutUpdateAvailable(result.tag ?? ''),
      UpdateOutcome.upToDate => l10n.aboutUpdateUpToDate,
      UpdateOutcome.noReleases => l10n.aboutUpdateNone,
      UpdateOutcome.rateLimited => l10n.aboutUpdateRateLimited,
      UpdateOutcome.offline => l10n.aboutUpdateOffline,
      UpdateOutcome.failed => l10n.aboutUpdateFailed,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
          if (result.outcome == UpdateOutcome.available)
            if (result.url case final url?)
              TextButton(
                onPressed: () => openExternal(context, url),
                child: Text(l10n.aboutOpenRelease),
              ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      // The address under the label, because the tile leaves the app: someone
      // handing a phone around should be able to see where a tap goes before
      // taking it.
      subtitle: Text(url, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => openExternal(context, url),
    );
  }
}

/// Hands a URL to the phone, and says so if nothing will take it.
///
/// `externalApplication` rather than the default: an in-app web view would put
/// a browser inside an app that holds an admin token, which is more surface
/// than four static links are worth.
///
/// No `canLaunchUrl` pre-flight. It needs the `<queries>` entry in the manifest
/// to answer honestly, it answers false for reasons that are not "this will
/// fail", and the failure it is meant to prevent is already visible in the
/// return value of `launchUrl`.
@visibleForTesting
Future<void> openExternal(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.aboutOpenFailed)));
  }
}
