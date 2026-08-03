package com.mfoss.garfin

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: `local_auth` shows an androidx
// BiometricPrompt, which is a Fragment and needs a FragmentActivity to attach
// to. The plugin checks rather than crashes — `LocalAuthPlugin.authenticate`
// answers NOT_FRAGMENT_ACTIVITY and no prompt is ever shown — so getting this
// wrong is a gate that silently never appears. Ground rule 9.
class MainActivity : FlutterFragmentActivity()
