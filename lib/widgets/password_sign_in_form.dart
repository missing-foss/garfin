// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The password fallback, for servers with Quick Connect switched off.
///
/// The password is held in a [TextEditingController] for as long as the form is
/// on screen and is handed straight to the repository. It is never stored, and
/// never logged — the no-`print` gate plus `redactSecrets` cover the accidental
/// route into a log; not writing one is what covers the deliberate one.
class PasswordSignInForm extends StatefulWidget {
  const PasswordSignInForm({
    super.key,
    required this.busy,
    required this.onSubmit,
  });

  final bool busy;
  final void Function(String username, String password) onSubmit;

  @override
  State<PasswordSignInForm> createState() => _PasswordSignInFormState();
}

class _PasswordSignInFormState extends State<PasswordSignInForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => widget.onSubmit(_username.text, _password.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _username,
          enabled: !widget.busy,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.usernameLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !widget.busy,
          obscureText: _obscured,
          textInputAction: TextInputAction.go,
          onSubmitted: widget.busy ? null : (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.passwordLabel,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscured = !_obscured),
              icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.signInAction),
        ),
      ],
    );
  }
}
