// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';

/// Hands a URL to the phone, and says so if nothing will take it.
///
/// `externalApplication` rather than the default: an in-app web view would put
/// a browser inside an app that holds an admin token, which is more surface
/// than a few static links are worth.
///
/// No `canLaunchUrl` pre-flight. It needs the `<queries>` entry in the manifest
/// to answer honestly, it answers false for reasons that are not "this will
/// fail", and the failure it is meant to prevent is already visible in the
/// return value of `launchUrl`.
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
