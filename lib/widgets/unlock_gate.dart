// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/unlock_providers.dart';
import '../screens/lock_screen.dart';

/// Wraps the whole app in the device unlock gate — ground rule 9.
///
/// It sits above sign-in as well as above everything after it, because
/// `docs/UI-SPEC.md` puts Unlock "before anything else", and because building
/// it in later would mean retrofitting every screen that had shipped in the
/// meantime (issue #18's reason for doing this at step 2).
///
/// The app stays in the tree behind the gate rather than being swapped out, so
/// locking on resume does not throw away the grid position or the sheet someone
/// was halfway through. It is covered by an opaque [LockScreen] and made
/// unreachable to both touch and screen readers while it is locked.
class UnlockGate extends ConsumerStatefulWidget {
  const UnlockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UnlockGate> createState() => _UnlockGateState();
}

class _UnlockGateState extends ConsumerState<UnlockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(lockControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        // `paused` only, never `inactive`. The system unlock prompt makes the
        // app inactive, so starting the idle clock there would mean the prompt
        // meant to end the lock was also what re-armed it.
        controller.noteBackgrounded();
      case AppLifecycleState.resumed:
        controller.noteResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(lockControllerProvider).isOpen;

    // StackFit.expand, so the lock screen is given the whole window rather than
    // shrink-wrapping and leaving the app visible around its edges.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: !open,
          child: IgnorePointer(ignoring: !open, child: widget.child),
        ),
        if (!open) const LockScreen(),
      ],
    );
  }
}
