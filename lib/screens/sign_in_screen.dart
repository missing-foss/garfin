// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/sign_in_providers.dart';
import '../repositories/jellyfin_exception.dart';
import '../widgets/error_notice.dart';
import '../widgets/password_sign_in_form.dart';
import '../widgets/quick_connect_panel.dart';
import '../widgets/server_address_form.dart';

/// Server address, then Quick Connect or password — `docs/UI-SPEC.md` § Sign in.
///
/// Stateful for three reasons that all belong to the screen rather than to the
/// app: the text controllers, the tab selection, and the lifecycle observer
/// that pokes the Quick Connect poller when the app comes back to the
/// foreground. Everything else is in the controllers.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.reason});

  /// Why the previous session ended, when it did not end by choice. Shown once,
  /// so a user who was signed out by a demoted account learns why instead of
  /// finding themselves back here for no stated reason.
  final JellyfinException? reason;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _serverAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverAddress = TextEditingController(
      text: ref.read(signInControllerProvider.notifier).rememberedServerUrl ??
          '',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverAddress.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Approving a Quick Connect code means leaving Garfin for Jellyfin, so a
    // resume is the strongest hint available that the code has just been
    // approved. Ask straight away rather than waiting out the backoff.
    if (state == AppLifecycleState.resumed) {
      ref.read(quickConnectControllerProvider.notifier).poke();
    }
  }

  void _useServer(String input) {
    ref.read(signInControllerProvider.notifier).useServer(input).then((_) {
      if (!mounted) return;
      // Show the address that will actually be used, scheme and all, rather
      // than leaving the user's shorthand on screen while Garfin talks to
      // something slightly different.
      final resolved = ref.read(signInControllerProvider).serverUrl;
      if (resolved != null) _serverAddress.text = resolved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(signInControllerProvider);
    final reason = widget.reason;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null) ...[
                ErrorNotice(message: jellyfinErrorText(l10n, reason)),
                const SizedBox(height: 16),
              ],
              if (state.malformedUrl) ...[
                ErrorNotice(message: l10n.errorMalformedServerAddress),
                const SizedBox(height: 16),
              ],
              if (state.error != null) ...[
                ErrorNotice(message: jellyfinErrorText(l10n, state.error!)),
                const SizedBox(height: 16),
              ],
              if (state.serverUrl == null)
                ServerAddressForm(
                  controller: _serverAddress,
                  busy: state.busy,
                  onSubmit: _useServer,
                )
              else
                _SignInMethods(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick Connect and password, or just password when the server has Quick
/// Connect switched off.
///
/// The tab is *absent* rather than disabled in that case: a tab that opens onto
/// an explanation of why it does nothing is worse than one that was never
/// offered (issue #17, `docs/JELLYFIN-API.md`).
class _SignInMethods extends ConsumerWidget {
  const _SignInMethods({required this.state});

  final SignInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final serverUrl = state.serverUrl!;

    final password = PasswordSignInForm(
      busy: state.busy,
      onSubmit: (username, secret) =>
          ref.read(signInControllerProvider.notifier).signInWithPassword(
                username: username,
                password: secret,
              ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.connectedTo(serverUrl), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () =>
              ref.read(signInControllerProvider.notifier).changeServer(),
          child: Text(l10n.changeServerLabel),
        ),
        const SizedBox(height: 16),
        if (state.quickConnectAvailable)
          _MethodTabs(serverUrl: serverUrl, password: password)
        else
          password,
      ],
    );
  }
}

class _MethodTabs extends ConsumerStatefulWidget {
  const _MethodTabs({required this.serverUrl, required this.password});

  final String serverUrl;
  final Widget password;

  @override
  ConsumerState<_MethodTabs> createState() => _MethodTabsState();
}

class _MethodTabsState extends ConsumerState<_MethodTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // TabController notifies rather than rebuilding: the IndexedStack below
    // reads `_tabs.index` directly, so without this a tab tap moves the
    // underline and nothing else.
    _tabs.addListener(_onTabChanged);
    // Quick Connect is the default (`docs/UI-SPEC.md`), so start the pairing as
    // soon as the tab exists rather than making the user ask for a code.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _start() {
    if (!mounted) return;
    ref
        .read(quickConnectControllerProvider.notifier)
        .start(widget.serverUrl);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quickConnect = ref.watch(quickConnectControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.signInMethodQuickConnect),
            Tab(text: l10n.signInMethodPassword),
          ],
        ),
        const SizedBox(height: 24),
        // A plain IndexedStack rather than a TabBarView: the panels are short
        // and different heights, and TabBarView would force them to the tallest
        // one inside a scroll view.
        IndexedStack(
          index: _tabs.index,
          sizing: StackFit.loose,
          children: [
            QuickConnectPanel(state: quickConnect, onRetry: _start),
            widget.password,
          ],
        ),
      ],
    );
  }
}
