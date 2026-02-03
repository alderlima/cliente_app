import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val backgroundGeolocation = project(":flutter_background_geolocation")
apply { from("${backgroundGeolocation.projectDir}/background_geolocation.gradle") }

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "org.traccar.client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "org.traccar.client"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Tenta ler das propriedades ou de variáveis de ambiente (para o CI)
            keyAlias = keystoreProperties["keyAlias"] as String? ?: System.getenv("SIGNING_KEY_ALIAS")
            keyPassword = keystoreProperties["keyPassword"] as String? ?: System.getenv("SIGNING_KEY_PASSWORD")
            storePassword = keystoreProperties["storePassword"] as String? ?: System.getenv("SIGNING_STORE_PASSWORD")
            val storeFilePath = keystoreProperties["storeFile"] as String? ?: "upload-keystore.jks"
            storeFile = file(storeFilePath)
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    lint {
        disable.add("NullSafeMutableLiveData")
    }
}

dependencies {
    implementation("org.slf4j:slf4j-api:2.0.7")
    implementation("com.github.tony19:logback-android:3.0.0")
}

flutter {
    source = "../.."
}
