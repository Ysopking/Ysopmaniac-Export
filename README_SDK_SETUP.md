# FindUX Mobile - SDK & Environment Setup

This document defines the "Ground Truth" for the development environment of FindUX Mobile.

## Required SDKs

### 1. Flutter SDK
- **Version**: `>=3.10.0` (Targeting stable branch)
- **Dart SDK**: `^3.0.0`

### 2. Android Environment
- **JDK**: Version 17+ (Required for latest Gradle versions)
- **Android SDK Platform**: API 34+
- **Build Tools**: 34.0.0+
- **Min SDK**: 21 (Required for `flutter_secure_storage`)
- **Target SDK**: 34

## Dependency Stack (Offline-First)

The following SDKs are implemented locally to ensure the **Zero-Server-Policy**:

- **State Management**: `flutter_riverpod` (^2.5.1) - Centralized logic control.
- **Persistence**: `hive` (^2.2.3) - Fast local encrypted database.
- **Security**: `local_auth` (^2.1.6) & `flutter_secure_storage` (^9.0.0) - Biometric and hardware keys.
- **WebView**: `flutter_inappwebview` (^6.0.0) - Stealth browsing layer.

## Setup Instructions

1. Ensure Flutter is installed: `flutter --version`
2. Fetch dependencies: `flutter pub get`
3. Generate local keys/adapters (if applicable): `flutter pub run build_runner build`
4. Run the app: `flutter run`

---
*Note: This project strictly follows the Zero-Server-Policy. All data remains 100% local.*
