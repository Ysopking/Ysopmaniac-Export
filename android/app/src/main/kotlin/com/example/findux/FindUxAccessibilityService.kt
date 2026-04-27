package com.example.findux

import android.accessibilityservice.AccessibilityService
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.content.Intent
import android.util.Log

class FindUxAccessibilityService : AccessibilityService() {

    private var lastVolumeUpTime: Long = 0
    private val DOUBLE_TAP_TIMEOUT = 500L

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val action = event.action

        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP && action == KeyEvent.ACTION_DOWN) {
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastVolumeUpTime < DOUBLE_TAP_TIMEOUT) {
                // Double Tap erkannt
                openFindUxOverlay()
                lastVolumeUpTime = 0 // Reset
                return true // Event konsumieren, damit Lautstärke sich nicht ändert
            }
            lastVolumeUpTime = currentTime
        }
        return super.onKeyEvent(event)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Nicht benötigt für Key-Events
    }

    override fun onInterrupt() {
        // Service unterbrochen
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("FindUX", "FindUX Accessibility Service connected")

        // TODO: Konfiguriere den Service für Volume-Key-Monitoring
        // serviceInfo.eventTypes = AccessibilityEvent.TYPE_VIEW_CLICKED or AccessibilityEvent.TYPE_KEY_EVENT
        // serviceInfo.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        // serviceInfo.flags = AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
    }

    // TODO: Methode zum Öffnen der FindUX-App als Overlay hinzufügen
    private fun openFindUxOverlay() {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}