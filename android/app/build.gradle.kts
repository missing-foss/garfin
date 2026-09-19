// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.missing_foss.garfin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.missing_foss.garfin"
        // 26 (Android 8.0) — flutter_secure_storage needs the AndroidKeyStore StrongBox path,
        // and Material You dynamic colour degrades gracefully below 31.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Both come from pubspec.yaml's `version:` (0.1.0+1 → versionName 0.1.0,
        // versionCode 1). Don't hardcode them here or they stop tracking pubspec.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ---------------------------------------------------------------------
    // SAFEGUARD (from missing-foss/trobar-android, via the Flutter scaffold):
    // every release must be signed with Garfin's own canonical key. If
    // GARFIN_KEYSTORE is ever pointed at the wrong or an old key, the
    // fingerprint won't match and the build fails loudly rather than shipping
    // an APK that can never be updated.
    //
    // Only runs when a keystore password is present (i.e. a real release
    // build) — debug builds and CI both skip it. The fingerprint itself is NOT
    // a secret: it is safe to publish, e.g. in the README, so anyone can
    // verify a downloaded APK against it. Only the keystore file and its
    // passwords are sensitive, and .gitignore excludes *.keystore/*.jks.
    //
    // `expected` is filled in and enforcing: a release build whose keystore
    // does not match the pinned fingerprint fails rather than producing an APK
    // that could never be installed as an update. It is not changed again
    // except deliberately -- a different value means a different key, and a
    // different key strands every existing install.
    // ---------------------------------------------------------------------
    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("GARFIN_KEYSTORE") ?: "release.keystore"
            val keystorePass = System.getenv("GARFIN_KEYSTORE_PASSWORD") ?: ""
            val alias = System.getenv("GARFIN_KEY_ALIAS") ?: "release"
            storeFile = file(keystorePath)
            storePassword = keystorePass
            keyAlias = alias
            keyPassword = System.getenv("GARFIN_KEY_PASSWORD") ?: keystorePass
            if (keystorePass.isNotEmpty() && file(keystorePath).exists()) {
                // This app's OWN key, not the other app's. The two were briefly
                // signed by one key; that was never a maintainer decision and
                // was corrected by generating a fresh key for this app while
                // the install base was still effectively zero.
                //
                // Filled in rather than left empty: an empty `expected` makes
                // the branch below a warning, and a guard that only warns is
                // one that has already let an unsignable build through once.
                val expected = "0b58bc2f1872c39df047ece3c3e0eda39d3f4f77107972f64c4ce8971be97155"
                val ks = KeyStore.getInstance("PKCS12")
                file(keystorePath).inputStream().use { ks.load(it, keystorePass.toCharArray()) }
                val cert = ks.getCertificate(alias) as? X509Certificate
                    ?: throw GradleException("Alias '$alias' not found in $keystorePath")
                val fp = MessageDigest.getInstance("SHA-256")
                    .digest(cert.encoded)
                    .joinToString("") { b -> "%02x".format(b) }
                if (expected.isNotEmpty() && fp != expected) {
                    throw GradleException(
                        "Release keystore fingerprint $fp does not match the canonical " +
                        "signing key ($expected). Refusing to build.")
                }
                if (expected.isEmpty()) {
                    logger.warn("Signing key fingerprint is $fp — paste this into `expected` above once, then never change it.")
                }
            }
        }
    }

    buildTypes {
        release {
            // No keystore present (CI, or a contributor without one) means an
            // unsigned-for-release build rather than a silent debug-key sign,
            // which is what Flutter's scaffold does by default.
            //
            // The condition is what makes that true. Assigned unconditionally,
            // Gradle's `validateSigningRelease` runs against a `storeFile` that
            // does not exist and the build fails outright:
            //
            //     Execution failed for task ':app:validateSigningRelease'.
            //     > Keystore file '…/release.keystore' not found for signing
            //       config 'release'.
            //
            // So the comment above described an intent the code did not
            // implement, and nobody could build a release APK without first
            // generating the canonical keystore (#20) — including CI, which
            // is why nothing here ever built release.
            val releaseSigning = signingConfigs.getByName("release")
            val keystorePresent = releaseSigning.storeFile?.exists() == true

            // File presence alone is not enough to decide this. It says whether
            // a keystore IS there, never whether one was MEANT to be — and the
            // difference is a release that silently ships unsigned.
            //
            // A maintainer exporting GARFIN_KEYSTORE_PASSWORD with a typo in
            // GARFIN_KEYSTORE, or on an unmounted volume, or on a runner whose
            // secret did not materialise, would otherwise get: a successful
            // build, an unsigned APK, the fingerprint safeguard above skipped
            // (it is guarded on the same `exists()`), and — because Flutter
            // copies the artifact onward — not even a `-unsigned` in the
            // filename to notice. Before #29 that case failed loudly.
            //
            // A non-empty password is the file's own definition of "a real
            // release build"; the safeguard block above already uses it. So an
            // intent to sign with nothing to sign with is a configuration
            // error, not an unsigned build.
            if (!keystorePresent &&
                !System.getenv("GARFIN_KEYSTORE_PASSWORD").isNullOrEmpty()) {
                throw GradleException(
                    "GARFIN_KEYSTORE_PASSWORD is set but no keystore exists at " +
                    "${releaseSigning.storeFile}. Refusing to build an unsigned " +
                    "release silently — fix the path, or unset the password to " +
                    "build unsigned on purpose.")
            }

            // The case the guard above cannot reach: *nothing* was set. With
            // neither a keystore nor a password there is genuinely nothing here
            // to distinguish "CI, or a contributor, building release on
            // purpose" -- which SECURITY.md and the forge workflow positively
            // permit -- from "a maintainer whose signing environment was never
            // sourced". Failing would break the first, so this is loud rather
            // than fatal.
            //
            // Loud matters because the quiet version has already happened: a
            // release APK was built, reported success, carried no `-unsigned`
            // in its name because Flutter copies the artifact onward and drops
            // Gradle's suffix, and went out for review before apksigner was
            // pointed at it. Nothing in the output distinguished it from a
            // signed build. `dev/verify.sh` is what CATCHES that, by reading
            // the artifact's real signing state back; this line is what makes
            // it visible in the build that produced it.
            //
            // `error` rather than `warn` or `lifecycle`, and not for severity:
            // `flutter build apk --release` passes Gradle's error level through
            // and swallows the other two, so anything quieter is a message
            // nobody ever reads. Verified on the pinned Flutter by building
            // with no signing environment and grepping the output -- see the
            // PR that added this; re-check it if the Flutter pin moves.
            //
            // Phrased as a standing fact rather than "building X now", because
            // this is configuration time: it is evaluated for a debug build
            // too, where "building an unsigned release APK" would be false.
            if (!keystorePresent) {
                logger.error(
                    "GARFIN: release builds will be UNSIGNED — no keystore at " +
                    "${releaseSigning.storeFile}. An unsigned APK cannot be " +
                    "installed or distributed. Source the signing environment " +
                    "to sign it.")
            }

            signingConfig = if (keystorePresent) releaseSigning else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ---------------------------------------------------------------------
// The app's first explicit Android dependency. Everything else compiled
// in here arrives through Flutter plugins, which declare their own.
//
// FreeDroidWarn shows the parent a dialog saying this app will stop
// installing on certified Android devices once Google's developer
// verification requirement lands. Garfin is distributed as a sideloaded
// APK from its Releases page, which is exactly the route that policy
// closes, and Android is the only platform in this repository -- so
// there is no part of the audience the warning does not apply to.
//
// EXACT TAG, NOT `V1.+`. Upstream's own README gives a dynamic version.
// A floating coordinate means the artifact can change under a build that
// is otherwise byte-identical, which is the property release signing
// exists to deny. Moving this is a deliberate act with a diff, the same
// as the pinned keystore fingerprint above.
// ---------------------------------------------------------------------
dependencies {
    implementation("com.github.woheller69:FreeDroidWarn:V1.14")
}
