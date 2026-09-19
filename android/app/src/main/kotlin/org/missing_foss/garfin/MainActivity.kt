package org.missing_foss.garfin

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.woheller69.freeDroidWarn.FreeDroidWarn

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
    // Set at creation and changed only by a deliberate act — never across a
    // lifecycle transition, which is the race the rejected alternative lost.
    // A parent flipping a switch in Settings is not that: nothing is being
    // beaten to a snapshot, the window simply has a different flag afterwards.
    //
    // **The recents thumbnail no longer depends on this flag from Android 13.**
    // `setRecentsScreenshotEnabled(false)` covers the snapshot on its own —
    // measured `since = 33` in the SDK's own `api-versions.xml`, against a
    // `minSdk` of 26. So on 33 and up a parent can allow screenshots and keep
    // the protection the flag was added for; below 33 there is no such API and
    // allowing screenshots gives the snapshot back. `SECURITY.md` says which
    // is which rather than implying one answer for every device.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
        // Secure until told otherwise: the setting is read on the Dart side a
        // moment later, and the safe state is the one that holds meanwhile.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WINDOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setScreenshotsAllowed" -> {
                        val allowed = call.arguments as? Boolean ?: false
                        if (allowed) {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    // Whether the recents thumbnail is covered without the
                    // flag. The Settings copy needs it: below 33 allowing
                    // capture gives the snapshot back, and that is the half a
                    // parent cannot infer.
                    "isRecentsCovered" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                    )
                    else -> result.notImplemented()
                }
            }

        // The certified-device warning, on its own channel rather than the
        // window one above: that channel is about FLAG_SECURE and what the
        // system may capture, and this shares none of it.
        //
        // **Dart drives the timing, and that is the whole point of routing it
        // through a channel at all.** Upstream's sample calls this from
        // onCreate. Here onCreate runs before the first Flutter frame and
        // before the unlock gate, so a dialog raised there stands in front of
        // someone who has not authenticated -- and two of its three buttons
        // are an ACTION_VIEW into a browser: "Details" opens
        // keepandroidopen.org and the red "Solution" button opens upstream's
        // own README. Only OK is inert. An app that deliberately sits behind a
        // parental gate should not hand the person holding the device a route
        // out to arbitrary web content before that gate has opened.
        //
        // Those destinations are upstream's defaults, kept deliberately rather
        // than inherited; THIRD_PARTY_NOTICES.md records them and says so.
        //
        // So the call site is Dart's, after the gate opens. Moving it back to
        // onCreate is one line and would look tidier; it is the thing not to
        // do.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WARNING_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showCertifiedDeviceWarning" -> {
                        // `this`, not applicationContext: it builds an
                        // AlertDialog, which needs a window to attach to.
                        //
                        // isFinishing/isDestroyed because the gate opening and
                        // the activity going away can race on a fast
                        // background -- showing into a dead window throws
                        // WindowManager.BadTokenException, which would cross
                        // the channel as a PlatformException and surface as a
                        // crash report about a dialog nobody saw.
                        if (!isFinishing && !isDestroyed) {
                            FreeDroidWarn.showWarningOnUpgrade(this, versionCode())
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The value the library compares against its stored `versionCodeWarn`.
    //
    // Read from PackageInfo rather than BuildConfig.VERSION_CODE, which is what
    // upstream's sample uses. BuildConfig is not generated in this module --
    // there is no buildFeatures block and the AGP default is off -- so the
    // sample does not compile here, and turning the feature on to obtain one
    // integer would add a generated class to every build for nothing.
    // PackageManager already knows the number, and it is the same number:
    // versionCode comes from pubspec.yaml via `flutter.versionCode`, is written
    // into the manifest at build time, and PackageInfo reads it back from
    // there.
    private fun versionCode(): Int {
        val info = packageManager.getPackageInfo(packageName, 0)
        // longVersionCode arrived in P and minSdk here is 26, so the
        // deprecated field is still the only option on the oldest supported
        // devices. toInt() takes the low 32 bits, which is where the
        // framework itself keeps versionCode.
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode
        }
    }

    private companion object {
        const val WINDOW_CHANNEL = "org.missing_foss.garfin/window"
        const val WARNING_CHANNEL = "org.missing_foss.garfin/device_warning"
    }
}
