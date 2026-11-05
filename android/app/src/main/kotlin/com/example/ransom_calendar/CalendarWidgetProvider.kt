package com.example.ransom_calendar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/// Home screen widget: today's agenda (up to 4 events + overflow count).
/// Dart writes today's events as JSON to shared prefs via home_widget;
/// this provider renders them into RemoteViews. Tapping opens the app.
class CalendarWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            val data = HomeWidgetPlugin.getData(context)
            val dateLabel = data.getString("widget_date", "") ?: ""
            val eventsJson = data.getString("widget_events", "[]") ?: "[]"
            views.setTextViewText(R.id.widget_title, "TODAY")
            views.setTextViewText(R.id.widget_date, dateLabel)

            val events = try { JSONArray(eventsJson) } catch (_: Exception) { JSONArray() }
            val rowIds = listOf(
                Triple(R.id.widget_event_0, R.id.widget_event_0_time, R.id.widget_event_0_title),
                Triple(R.id.widget_event_1, R.id.widget_event_1_time, R.id.widget_event_1_title),
                Triple(R.id.widget_event_2, R.id.widget_event_2_time, R.id.widget_event_2_title),
                Triple(R.id.widget_event_3, R.id.widget_event_3_time, R.id.widget_event_3_title),
            )
            for (i in rowIds.indices) {
                val (row, timeId, titleId) = rowIds[i]
                if (i < events.length()) {
                    val e = events.getJSONObject(i)
                    views.setViewVisibility(row, View.VISIBLE)
                    views.setTextViewText(timeId, e.optString("time", ""))
                    views.setTextViewText(titleId, e.optString("title", ""))
                } else {
                    views.setViewVisibility(row, View.GONE)
                }
            }
            if (events.length() == 0) {
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_empty, View.GONE)
            }
            val extra = events.length() - rowIds.size
            if (extra > 0) {
                views.setViewVisibility(R.id.widget_more, View.VISIBLE)
                views.setTextViewText(R.id.widget_more, "+$extra MORE")
            } else {
                views.setViewVisibility(R.id.widget_more, View.GONE)
            }

            // Tap anywhere on the widget opens the app.
            val intent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val pending = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(android.R.id.background, pending)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
