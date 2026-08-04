package com.mfoss.garfin

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
class MainActivity : FlutterFragmentActivity()
