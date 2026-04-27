package com.example.findux

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.content.Intent
import android.util.Log

class FindUxAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // TODO: Hier das Doppeltippen auf die Lauter-Taste abfangen
        // Verwende AccessibilityEvent für Volume-Key-Events
        // Wenn doppelt getippt, öffne die FindUX-App als Overlay

        Log.d("FindUX", "Accessibility Event: ${event?.eventType}")
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