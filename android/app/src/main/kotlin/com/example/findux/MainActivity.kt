package com.example.findux

import android.os.Bundle
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

    // Zustand: Ist InAppWebView gerade aktiv?
    @Volatile private var inWebView = false

    // Zeitstempel der letzten Screenshot-Anfragen (rate limiter)
    private val screenshotTimestamps = mutableListOf<Long>()

    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE IMMER und BEDINGUNGSLOS setzen — kein Toggle, keine Ausnahme.
        // Gilt fuer alle Build-Typen (debug + release).
        // Screenshot-Schutz greift schon beim allerersten Frame (vor Flutter-Render).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // ── InAppWebView betreten ────────────────────────────────────
                // FLAG_SECURE wird NUR waehrend einer aktiven WebView-Session
                // temporaer aufgehoben — NIEMALS ausserhalb.
                "enterWebView" -> {
                    synchronized(screenshotTimestamps) {
                        inWebView = true
                        screenshotTimestamps.clear()
                    }
                    runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }

                // ── InAppWebView verlassen ───────────────────────────────────
                // FLAG_SECURE sofort wieder hart setzen.
                "exitWebView" -> {
                    synchronized(screenshotTimestamps) {
                        inWebView = false
                        screenshotTimestamps.clear()
                    }
                    runOnUiThread {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    }
                    result.success(true)
                }

                // ── Screenshot anfordern (rate-limited) ─────────────────────
                // Darf NUR aus InAppWebView aufgerufen werden.
                // Gibt true zurueck wenn noch Tokens verfuegbar (< 3 / 30 s),
                // sonst false — Flutter darf den Screenshot dann NICHT machen.
                "requestScreenshot" -> {
                    synchronized(screenshotTimestamps) {
                        if (!inWebView) {
                            // Strikt: ausserhalb von WebView niemals erlaubt
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val now = System.currentTimeMillis()
                        // Eintraege ausserhalb des 30-Sekunden-Fensters entfernen
                        screenshotTimestamps.removeAll { now - it > SCREENSHOT_WINDOW_MS }
                        if (screenshotTimestamps.size < MAX_SCREENSHOTS_PER_WINDOW) {
                            screenshotTimestamps.add(now)
                            result.success(true)
                        } else {
                            // Limit erreicht: naechste erlaubte Zeit berechnen
                            val oldest = screenshotTimestamps.minOrNull() ?: now
                            val waitMs = SCREENSHOT_WINDOW_MS - (now - oldest)
                            result.success(false)
                            android.util.Log.d(
                                "FindUX/Security",
                                "Screenshot rate limit: $MAX_SCREENSHOTS_PER_WINDOW/" +
                                "${SCREENSHOT_WINDOW_MS / 1000}s. Warte ${waitMs / 1000}s."
                            )
                        }
                    }
                }

                // ── Diagnose: ist FLAG_SECURE aktuell gesetzt? ──────────────
                "isSecure" -> {
                    val flags = window.attributes.flags
                    val on = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                    result.success(on)
                }

                else -> result.notImplemented()
            }
        }
    }
}
