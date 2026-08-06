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
    namespace = "com.mfoss.garfin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mfoss.garfin"
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
    // The key was generated for Garfin alone in #20 — **never** share one with
    // trobar-android, or whoever holds either key can push updates to both —
    // and `expected` below is pinned to it. Never change that constant except
    // deliberately: an APK signed with a different key cannot update an
    // installed Garfin.
    //
    // The `expected.isEmpty()` branch further down is the bootstrap path, kept
    // for a deliberate rotation: blank the constant, build once, read the
    // fingerprint out of the warning, paste it back. It is dead code in normal
    // use, which is the intended state.
    // ---------------------------------------------------------------------
    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("GARFIN_KEYSTORE") ?: "release.keystore"
            val keystorePass = System.getenv("GARFIN_KEYSTORE_PASSWORD") ?: ""
            // Defaults to the canonical key's own alias. A default that did not
            // match the one key this repo signs with would be a trap by
            // construction — it fails with "Alias 'release' not found", which
            // is loud but avoidable.
            val alias = System.getenv("GARFIN_KEY_ALIAS") ?: "garfin"
            storeFile = file(keystorePath)
            storePassword = keystorePass
            keyAlias = alias
            keyPassword = System.getenv("GARFIN_KEY_PASSWORD") ?: keystorePass
            if (keystorePass.isNotEmpty() && file(keystorePath).exists()) {
                // Garfin's canonical signing key, generated 2026-08-06 (#20) and
                // pinned here after the first signed build. **Never change this
                // except deliberately**: an APK signed with a different key
                // cannot update an installed Garfin, and the guard below is
                // what stops that shipping by accident.
                //
                // Not a secret — it is published in SECURITY.md so anyone can
                // check a downloaded APK with
                // `apksigner verify --print-certs`.
                val expected = "2e815848c120b612589a5999a43e0c30555b0f2a1c7d46abae2fc181c1819f95"
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
            // is why nothing here ever built release. See #29, #30.
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
