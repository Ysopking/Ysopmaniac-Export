# 📋 FindUX Build-Checkliste

Diese Liste fasst alle Voraussetzungen für einen erfolgreichen Build der APK zusammen, besonders für die GitHub Cloud-Pipeline.

## 1. Android-Infrastruktur
- [ ] **`android/gradle.properties`**: Muss `android.useAndroidX=true` und `android.enableJetifier=true` enthalten.
- [ ] **`android/settings.gradle`**: Muss einen Fallback für `FLUTTER_ROOT` enthalten, da `local.properties` in der Cloud fehlt.
- [ ] **Plugin-Reihenfolge**: In `app/build.gradle` muss das Flutter-Plugin **nach** den Android- und Kotlin-Plugins angewendet werden.

## 2. Ressourcen & Assets
- [ ] **Launcher-Icons**: Alle Bilder in `mipmap-*` und `drawable-*` müssen hochgeladen sein. (Nutze `git add -f`, falls sie ignoriert werden).
- [ ] **Styles**: Nutze nur Standard-Themes (`@android:style/Theme.Light.NoTitleBar`), um AAPT-Fehler zu vermeiden.
- [ ] **Leere Ordner**: Stelle sicher, dass `assets/data/` eine `.gitkeep` Datei enthält.

## 3. Flutter & Dart Logik
- [ ] **Syntax**: Keine Methoden außerhalb von Klassen in `home_page.dart`.
- [ ] **L10n**: Datei `l10n.yaml` muss im Hauptverzeichnis vorhanden sein.
- [ ] **SDK Version**: In `pubspec.yaml` muss `sdk: '>=3.3.0 <4.0.0'` stehen.
- [ ] **Importe**: Überprüfe auf Tippfehler (z.B. `riverpod` statt `riverbed`).

## 4. GitHub Actions
- [ ] **Node.js**: Der Workflow sollte Node.js 24 nutzen, um Deprecation-Warnungen zu vermeiden.
- [ ] **Runner**: Nutze `ubuntu-latest` und `flutter-version: '3.22.0'`.
