package com.example.findux

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity statt FlutterActivity ist Pflicht fuer das
// local_auth Plugin (BiometricPrompt erwartet eine FragmentActivity).
// Ohne diesen Wechsel oeffnet sich der Biometrie-Dialog nicht und der
// Authenticate-Call schlaegt still fehl.
class MainActivity: FlutterFragmentActivity() {

    // Stage F Haertung: FLAG_SECURE blockt Screenshots, Screen-Recordings
    // und das Recents-Thumbnail. Wird hier nativ gesetzt — frueher als
    // Flutter ueberhaupt rendert. Damit ist der allererste Frame
    // (auch der Splash) bereits geschuetzt. Eine externe Plugin-
    // Dependency (z.B. flutter_windowmanager) waere unnoetig und
    // bricht regelmaessig mit neueren AGP-Versionen.
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
