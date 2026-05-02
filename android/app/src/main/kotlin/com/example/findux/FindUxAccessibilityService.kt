package io.findux.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class FindUxAccessibilityService : AccessibilityService() {

    private var lastVolumeUpTime: Long = 0
    private val DOUBLE_TAP_TIMEOUT = 500L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("FindUX", "FindUX Accessibility Service verbunden")

        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags = AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        info.notificationTimeout = 100
        serviceInfo = info
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val action = event.action

        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP && action == KeyEvent.ACTION_DOWN) {
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastVolumeUpTime < DOUBLE_TAP_TIMEOUT) {
                // Doppel-Tap erkannt → FindUX öffnen
                openFindUx()
                lastVolumeUpTime = 0L // Reset
                return true // Volume-Änderung unterdrücken
            }
            lastVolumeUpTime = currentTime
        }
        return super.onKeyEvent(event)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Nicht benötigt für Key-Events
    }

    override fun onInterrupt() {
        Log.d("FindUX", "FindUX Accessibility Service unterbrochen")
    }

    private fun openFindUx() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        startActivity(intent)
    }
}
