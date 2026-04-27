package com.example.findux.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.findux.MainActivity
import com.example.findux.R

class FindUxWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        // RemoteViews für das Widget erstellen
        val views = RemoteViews(context.packageName, R.layout.widget_findux)

        // Intent zum Öffnen der MainActivity
        val intent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        // Button mit PendingIntent verknüpfen
        views.setOnClickPendingIntent(R.id.widgetButton, pendingIntent)

        // Widget aktualisieren
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    // TODO: Hier die Widget-Logik erweitern
    // - Direkt-Suche aus dem Widget ermöglichen
    // - Schnellzugriff auf häufige Suchen
}