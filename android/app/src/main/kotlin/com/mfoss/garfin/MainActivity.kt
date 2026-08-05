package com.mfoss.garfin

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: `local_auth` shows an androidx
// BiometricPrompt, which is a Fragment and needs a FragmentActivity to attach
// to. Ground rule 9.
//
// Reverting this would not crash and would not pass silently either: the plugin
// answers NOT_FRAGMENT_ACTIVITY, which becomes LocalAuthException(uiUnavailable)
// -> UnlockOutcome.error, and the gate stays up showing `unlockError` with a
// live button. Visible failure, which is the right kind — but it is a gate that
// can never be opened, so it still wants noticing.
class MainActivity : FlutterFragmentActivity() {
    // FLAG_SECURE, for the task-switcher thumbnail. Ground rule 9, issue #26.
    //
    // Without it Android snapshots the window on the way out and writes the
    // image to /data/system_ce/0/snapshots/<taskId>.jpg. Measured 2026-08-05,
    // and it is worse than a live thumbnail: the file survives the idle
    // timeout byte-identical, so resuming demands auth while the switcher
    // still shows content from before the app relocked. The gate locks on
    // resume; it cannot cover the snapshot, because the snapshot is taken on
    // the way out.
    //
    // Chosen over covering on `paused`, which would avoid the cost below but
    // has to win a race against when WindowManager takes the snapshot, and
    // nothing here controls whether a Flutter frame rasterises before that.
    // FLAG_SECURE is refused by the system rather than beaten by timing, so
    // there is no race to lose. The cost is real and accepted: the parent
    // cannot screenshot Garfin or mirror it to another screen.
    //
    // Blanket and set once, not toggled per screen — toggling window flags
    // across lifecycle transitions reintroduces the race this exists to avoid.
    // See docs/DECISIONS.md.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
