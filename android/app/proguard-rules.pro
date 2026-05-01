# Flutter
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Flutter InAppWebView
-keep class com.pichillilorenzo.** { *; }
-keep class org.chromium.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**
-dontwarn org.chromium.**

# Kotlin
-dontwarn kotlin.**
-dontnote kotlin.**