import java.io.File
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystoreFile = File(rootProject.projectDir, "key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(FileInputStream(keystoreFile))
} else {
    error("key.properties file not found in project root")
}


plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // FlutterFire, if used
}

android {
    namespace = "com.example.bussiness_keeping_new"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.bussiness_keeping_new"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"]?.toString()
                ?: error("keyAlias missing in key.properties")
            keyPassword = keystoreProperties["keyPassword"]?.toString()
                ?: error("keyPassword missing in key.properties")
            storeFile = keystoreProperties["storeFile"]?.toString()?.let { file(it) }
                ?: error("storeFile missing in key.properties")
            storePassword = keystoreProperties["storePassword"]?.toString()
                ?: error("storePassword missing in key.properties")
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
