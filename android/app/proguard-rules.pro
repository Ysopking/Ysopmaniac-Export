# ════════════════════════════════════════════════════════════════════════════
# FindUX — ProGuard / R8 Regeln
# Ziel: maximale Verschleierung des Kotlin-Codes bei vollem Flutter-Betrieb.
# ════════════════════════════════════════════════════════════════════════════

# ── Flutter Core ────────────────────────────────────────────────────────────
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.embedding.engine.FlutterEngine { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }
-keep class io.flutter.embedding.android.FlutterActivity { *; }

# ── FindUX Native Code ───────────────────────────────────────────────────────
-keep class io.findux.app.MainActivity { *; }

# ── Accessibility Service ────────────────────────────────────────────────────
-keep class * extends android.accessibilityservice.AccessibilityService { *; }

# ── Flutter InAppWebView ─────────────────────────────────────────────────────
-keep class com.pichillilorenzo.** { *; }
-keep class org.chromium.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**
-dontwarn org.chromium.**

# ── Flutter Plugins (generell) ───────────────────────────────────────────────
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }

# ── Kotlin Standard Library ──────────────────────────────────────────────────
-dontwarn kotlin.**
-dontnote kotlin.**
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Lazy { <methods>; }

# ── Coroutines ───────────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ── Biometrie (local_auth Plugin) ────────────────────────────────────────────
-keep class androidx.biometric.** { *; }
-keep class androidx.fragment.app.** { *; }
-dontwarn androidx.biometric.**

# ── shared_preferences ───────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ── flutter_secure_storage ───────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.**

# ── Google Play Core (Flutter Deferred Components) ───────────────────────────
# Die Flutter-Engine referenziert intern Play-Core-Klassen fuer deferred
# Components / Dynamic Delivery. Da FindUX kein Play Store Delivery nutzt,
# fehlen diese Klassen im APK-Classpath. R8 soll sie ignorieren statt den
# Build abzubrechen.
-dontwarn com.google.android.play.core.**

# ── Stack Traces lesbar halten (nur lokal!) ──────────────────────────────────
-printmapping mapping.txt
