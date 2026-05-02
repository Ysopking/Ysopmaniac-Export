package com.example.findux

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity statt FlutterActivity ist Pflicht fuer das
// local_auth Plugin (BiometricPrompt erwartet eine FragmentActivity).
// Ohne diesen Wechsel oeffnet sich der Biometrie-Dialog nicht und der
// Authenticate-Call schlaegt still fehl.
class MainActivity : FlutterFragmentActivity() {

    companion object {
        // Kanal-Name muss EXAKT mit dem Flutter-Pendant in
        // lib/services/secure_flag.dart uebereinstimmen.
        private const val SECURITY_CHANNEL = "com.findux/security"

        // Die SharedPreferences des shared_preferences-Plugins liegen in
        // dieser Datei; alle Keys werden mit dem Prefix "flutter."
        // gespeichert. Wir lesen den Wert hier nativ, BEVOR Flutter
        // ueberhaupt rendert, damit FLAG_SECURE auch den allerersten
        // Frame (Splash) abdeckt.
        private const val PREFS_FILE = "FlutterSharedPreferences"
        private const val PREFS_KEY_SECURE = "flutter.disableScreenshots"
        private const val PREFS_DEFAULT_SECURE = true
    }

    // Stage 14 Haertung: FLAG_SECURE wird jetzt persistiert + togglebar.
    // Default ist ON (privacy-by-default). Beim onCreate lesen wir den
    // letzten User-Entscheid aus den SharedPreferences und wenden ihn
    // sofort an — noch BEVOR Flutter rendert. Zur Laufzeit kann der
    // User den Schalter in den Settings umlegen; das ruft dann ueber
    // den MethodChannel setSecure auf, was FLAG_SECURE setzt/clear.
    override fun onCreate(savedInstanceState: Bundle?) {
        applySecureFlagFromPrefs()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    runOnUiThread { setSecureFlag(enable) }
                    result.success(true)
                }
                "isSecure" -> {
                    val flags = window.attributes.flags
                    val on = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                    result.success(on)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun applySecureFlagFromPrefs() {
        val prefs = getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        val on = prefs.getBoolean(PREFS_KEY_SECURE, PREFS_DEFAULT_SECURE)
        setSecureFlag(on)
    }

    private fun setSecureFlag(enable: Boolean) {
        if (enable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
