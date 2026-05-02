package com.example.findux

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity statt FlutterActivity ist Pflicht fuer das
// local_auth Plugin (BiometricPrompt erwartet eine FragmentActivity).
// Ohne diesen Wechsel oeffnet sich der Biometrie-Dialog nicht und der
// Authenticate-Call schlaegt still fehl.
class MainActivity: FlutterFragmentActivity() {
}
