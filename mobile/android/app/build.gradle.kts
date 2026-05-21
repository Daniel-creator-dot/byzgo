import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}
fun readMapsKeyFromRepoEnvLocal(): String {
    val envFile = rootProject.file("../../.env.local")
    if (!envFile.exists()) return ""
    val prefix = Regex("""^\s*(?:GOOGLE_MAPS_API_KEY|VITE_GOOGLE_MAPS_API_KEY)\s*=\s*(.+)\s*$""")
    envFile.readLines().forEach { line ->
        val m = prefix.find(line.trim())
        if (m != null) {
            return m.groupValues[1].trim().trim('"').trim('\'')
        }
    }
    return ""
}

val googleMapsApiKey: String = (
    localProperties.getProperty("GOOGLE_MAPS_API_KEY")
        ?: readMapsKeyFromRepoEnvLocal()
        ?: System.getenv("GOOGLE_MAPS_API_KEY")
        ?: ""
    ).also { key ->
        if (key.isNotEmpty()) {
            println("BytzGo: Google Maps API key loaded for Android (${key.takeLast(6)}…) ")
        } else {
            println("BytzGo: WARNING — no GOOGLE_MAPS_API_KEY (add to android/local.properties or repo .env.local)")
        }
    }

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.bytzgo.bytzgo_mobile"
    compileSdk = maxOf(35, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Play Store: must not use com.example.* — match google-services.json (Firebase bytzgo-9bd89).
        applicationId = "net.bytzgo.app"
        minSdk = flutter.minSdkVersion
        // Play requires recent target API (see docs/PLAY_STORE_REJECTION_AUDIT.md).
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                println("BytzGo: WARNING — android/key.properties missing; release uses debug signing (not valid for Play Store)")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
