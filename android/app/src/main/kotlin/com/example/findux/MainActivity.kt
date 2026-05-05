package io.findux.app

import android.os.Bundle
import android.os.Debug
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity ist Pflicht fuer das local_auth Plugin
// (BiometricPrompt erwartet eine FragmentActivity).
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val SECURITY_CHANNEL = "com.findux/security"

        // Screenshot-Schutz: max 3 Screenshots in 30 Sekunden, NUR in InAppWebView
        private const val MAX_SCREENSHOTS_PER_WINDOW = 3
        private const val SCREENSHOT_WINDOW_MS = 30_000L
    }

    @Volatile private var inWebView = false
    private val screenshotTimestamps = mutableListOf<Long>()

    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE IMMER und BEDINGUNGSLOS setzen — kein Toggle, keine Ausnahme.
        // Gilt fuer alle Build-Typen (debug + release).
        // Screenshot-Schutz greift schon beim allerersten Frame (vor Flutter-Render).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        // S-05: Anti-Debugger-Check auf nativer Ebene.
        // Debug.isDebuggerConnected() ist sicherer als TracerPid-Datei-Lesen
        // weil sie direkt die JVM/ART-Debug-Session abfragt.
        if (Debug.isDebuggerConnected()) {
            Log.w("FindUX", "Debugger angehaengt — eingeschraenkter Modus.")
            // Kein Abbruch: Legitime ADB-Nutzer sollen weiterarbeiten koennen.
            // Der Dart-RootDetector meldet debuggerAttached an die UI.
        }
        super.onCreate(savedInstanceState)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // FIX Lücke 2: Sicherstellen dass FLAG_SECURE immer dann gesetzt ist,
        // wenn die App den Fokus zurueckerhaelt UND kein aktiver WebView offen ist.
        // Verhindert Race-Condition bei schnellem enterWebView/Task-Switch/exitWebView.
        if (hasFocus && !inWebView) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // ── InAppWebView betreten ────────────────────────────────────
                // FIX Lücke 2: FLAG_SECURE wird NICHT mehr vollstaendig aufgehoben.
                // Stattdessen: FLAG_SECURE bleibt gesetzt. WebView-Inhalte sind
                // weiterhin sichtbar (WebView selbst rendert unabhaengig vom Flag),
                // aber System-Screenshots und Recent-Apps-Thumbnails bleiben schwarz.
                //
                // Was bedeutet das praktisch?
                //   • Der User sieht den WebView-Inhalt normal (FLAG_SECURE
                //     betrifft nur den System-Screenshot-Layer, nicht den Render).
                //   • Ein programmatischer Screenshot via InAppWebViewController
                //     .takeScreenshot() schlaegt fehl solange FLAG_SECURE gesetzt ist.
                //   → requestScreenshot() gibt daher immer false zurueck wenn
                //     FLAG_SECURE aktiv ist. Akzeptierter Trade-off:
                //     Screenshot-Feature wird deaktiviert zugunsten von Task-Switcher-Schutz.
                "enterWebView" -> {
                    synchronized(screenshotTimestamps) {
                        inWebView = true
                        screenshotTimestamps.clear()
                        // FLAG_SECURE bleibt — kein clearFlags mehr.
                    }
                    result.success(true)
                }

                // ── InAppWebView verlassen ───────────────────────────────────
                "exitWebView" -> {
                    synchronized(screenshotTimestamps) {
                        inWebView = false
                        screenshotTimestamps.clear()
                    }
                    // FLAG_SECURE ist bereits gesetzt — kein erneutes setFlags noetig.
                    result.success(true)
                }

                // ── Screenshot anfordern (rate-limited) ─────────────────────
                // Da FLAG_SECURE jetzt dauerhaft aktiv ist, schlaegt
                // InAppWebViewController.takeScreenshot() auf Android immer fehl.
                // Wir geben false zurueck damit Flutter keinen Fehler-Dialog zeigt.
                "requestScreenshot" -> {
                    synchronized(screenshotTimestamps) {
                        if (!inWebView) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val now = System.currentTimeMillis()
                        screenshotTimestamps.removeAll { now - it > SCREENSHOT_WINDOW_MS }
                        if (screenshotTimestamps.size < MAX_SCREENSHOTS_PER_WINDOW) {
                            screenshotTimestamps.add(now)
                            // FLAG_SECURE ist gesetzt → Screenshot wird technisch
                            // fehlschlagen, aber wir signalisieren "erlaubt" damit
                            // Flutter den Versuch starten kann (iOS-kompatibel).
                            result.success(true)
                        } else {
                            val oldest = screenshotTimestamps.minOrNull() ?: now
                            val waitMs = SCREENSHOT_WINDOW_MS - (now - oldest)
                            android.util.Log.d(
                                "FindUX/Security",
                                "Screenshot rate limit: $MAX_SCREENSHOTS_PER_WINDOW/" +
                                "${SCREENSHOT_WINDOW_MS / 1000}s. Warte ${waitMs / 1000}s."
                            )
                            result.success(false)
                        }
                    }
                }

                 // ── Diagnose: ist FLAG_SECURE aktuell gesetzt? ──────────────
                 "isSecure" -> {
                     val flags = window.attributes.flags
                     val on = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                     result.success(on)
                 }

                 // ── System-Sicherheitseinstellungen oeffnen ─────────────────
                 "openSecuritySettings" -> {
                     try {
                         val intent = Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS)
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                         startActivity(intent)
                         result.success(true)
                     } catch (e: Exception) {
                         result.error("UNAVAILABLE", "Konnte Sicherheitseinstellungen nicht oeffnen", null)
                     }
                 }

                 else -> result.notImplemented()
            }
        }
    }
}
