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
    // `expected` starts empty on purpose: generate a brand-new keystore for
    // Garfin (do NOT reuse trobar-android's), build once with it, read the
    // fingerprint from the warning this prints, paste it in below, then never
    // change it again except deliberately.
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
                val expected = "" // TODO: fill in after the first real signed build
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
            signingConfig =
                if (releaseSigning.storeFile?.exists() == true) releaseSigning else null
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
