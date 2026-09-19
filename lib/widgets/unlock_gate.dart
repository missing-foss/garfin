// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../providers/unlock_providers.dart';
import '../screens/lock_screen.dart';

/// Wraps the signed-in app in the device unlock gate — ground rule 9.
///
/// **Not sign-in.** It used to sit above that too, on the reading that
/// `docs/UI-SPEC.md` put Unlock "before anything else". Before a session there
/// is no token, no server address and no children, so that guarded an empty app
/// and asked for biometrics from someone who had not typed an address yet; #69
/// moved it into `AppRoot`'s signed-in branch, where the rule's premise is
/// actually true. What has not changed is that it was built at step 2 rather
/// than retrofitted later (issue #18).
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
  /// Whether the post-frame callback that asks for the warning has been
  /// scheduled for this gate.
  ///
  /// Belt and braces with `DeviceWarning.showIfDue`, which is the guard that
  /// actually matters — it survives this widget being rebuilt or remounted, and
  /// this flag does not. What this one prevents is a *queue* of post-frame
  /// callbacks: [build] runs on every relock and unlock, and scheduling one
  /// each time would be harmless but pointless.
  bool _warningScheduled = false;

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

    // The certified-device warning waits for the gate, and this is the only
    // place that knows it has opened.
    //
    // Not from `MainActivity.onCreate`, where upstream's sample puts it: that
    // runs before the first Flutter frame and before this gate, so the dialog
    // would stand in front of someone who has not authenticated — and two of
    // its three buttons are an ACTION_VIEW out to a browser. The gate exists to
    // decide who gets past it; a notice raised in front of it is a way around
    // it, however small.
    //
    // Deferred to after the frame rather than called here: this is a side
    // effect with a platform round-trip in it, and `build` must stay free of
    // both. `mounted` is re-checked on the other side because the gate can be
    // disposed between the two — signing out disposes this subtree.
    if (open && !_warningScheduled) {
      _warningScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(deviceWarningProvider).showIfDue();
      });
    }

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
