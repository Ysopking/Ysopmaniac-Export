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
# MainActivity + MethodChannel-Handler muessen erhalten bleiben
# (Flutter ruft sie ueber Reflection auf).
-keep class io.findux.app.MainActivity { *; }
# S-09: Keine Wildcard-keep-Regel fuer eigene Klassen — R8 darf alles verschleiern.
# Nur MainActivity ist wegen MethodChannel-Reflection exempt.

# ── Accessibility Service ────────────────────────────────────────────────────
# FindUxAccessibilityService.kt: Android bindet ihn per Manifest, darf nicht
# umbenannt werden.
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

# ── Verschleierung: Bibliotheken die nicht umbenannt werden duerfen ──────────
# R8 darf alles andere aggressiv umbenennen — das ist gewuenscht!
# Keine -keep-Regeln fuer interne Dart-gespiegelte Klassen noetig:
# Der Dart-Code lebt in libapp.so, nicht im Dex-Code.

# ── Stack Traces lesbar halten (nur lokal!) ──────────────────────────────────
# Den ./debug_info Ordner (aus --split-debug-info) NIEMALS veroeffentlichen.
# Er wird benoetigt um obfuszierte Crashes zu entschluesseln:
#   flutter symbolize -i <crash.txt> -d ./debug_info
-printmapping mapping.txt
