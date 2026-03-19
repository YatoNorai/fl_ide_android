plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fl_ide"
    compileSdk = 36 //flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.termux" //"com.example.fl_ide"
        minSdk = 26  // Required for PTY/rootfs operations
        targetSdk = 28  // Must stay 28: Android 10+ SELinux blocks execve() from
                        // app data dirs (/data/data/com.termux/files/usr/bin/)
                        // for targetSdk >= 29. The real Termux F-Droid app also
                        // uses targetSdk 28 for this exact reason.
                        // Lint warning suppressed below via lint { disable }.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    lint {
        disable += "ExpiredTargetSdkVersion"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
