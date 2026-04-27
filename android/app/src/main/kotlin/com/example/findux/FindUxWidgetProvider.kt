package com.example.findux

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class FindUxWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        // RemoteViews für das Widget erstellen (Nutzt den korrekten Layout-Namen)
        val views = RemoteViews(context.packageName, R.layout.widget_layout)

        // Intent zum Öffnen der MainActivity
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(context, 0, intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        // Button/Layout mit PendingIntent verknüpfen
        views.setOnClickPendingIntent(R.id.widget_button, pendingIntent)
        views.setOnClickPendingIntent(R.id.widget_text, pendingIntent)

        // Widget aktualisieren
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
