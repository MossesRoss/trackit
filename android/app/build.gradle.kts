// Author: Mosses
// Version: 1.1.0
// Changelog: Added missing java.util.Properties and java.io.FileInputStream imports to fix build errors.

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// START: Added for release signing
// Read the key.properties file
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
// END: Added for release signing

android {
    namespace = "com.mosses.trackit"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    } 

    kotlinOptions {
        jvmTarget = "11"
    }

    // START: Added for release signing
    // Define the "release" signing configuration
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    // END: Added for release signing

    defaultConfig {
        applicationId = "com.mosses.trackit"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // CHANGED: Tell release builds to use your new "release" config
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}