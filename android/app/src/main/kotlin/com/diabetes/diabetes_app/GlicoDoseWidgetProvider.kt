package com.diabetes.diabetes_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class GlicoDoseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.glicodose_widget)

            val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_root, openApp)

            val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("glicodose://syncLibre"),
            )
            views.setOnClickPendingIntent(R.id.widget_sync, syncIntent)

            val connected = widgetData.getBoolean("libre_connected", false)
            val hasGlucose = widgetData.getBoolean("has_glucose", false)
            val glucose = widgetData.getInt("glucose_mgdl", 0)
            val trend = widgetData.getString("trend_label", "").orEmpty()
            val age = widgetData.getString("glucose_age", "").orEmpty()
            val iob = widgetData.getInt("iob_u", 0)
            val syncing = widgetData.getBoolean("syncing", false)
            val lastError = widgetData.getString("last_error", "").orEmpty()

            val defaultInk = ContextCompat.getColor(context, R.color.widget_ink)

            if (connected && hasGlucose && glucose > 0) {
                views.setTextViewText(R.id.widget_glucose, glucose.toString())
                views.setTextViewText(R.id.widget_trend, trend)
                val glucoseColor = ContextCompat.getColor(context, glucoseColorRes(glucose))
                views.setTextColor(R.id.widget_glucose, glucoseColor)
                views.setTextColor(R.id.widget_trend, glucoseColor)
                val meta = buildString {
                    append("mg/dL")
                    if (age.isNotEmpty()) {
                        append(" · ")
                        append(age)
                    }
                }
                views.setTextViewText(R.id.widget_glucose_meta, meta)
            } else if (connected) {
                views.setTextViewText(R.id.widget_glucose, "—")
                views.setTextViewText(R.id.widget_trend, "")
                views.setTextColor(R.id.widget_glucose, defaultInk)
                views.setTextColor(R.id.widget_trend, defaultInk)
                views.setTextViewText(R.id.widget_glucose_meta, "Libre conectado")
            } else {
                views.setTextViewText(R.id.widget_glucose, "—")
                views.setTextViewText(R.id.widget_trend, "")
                views.setTextColor(R.id.widget_glucose, defaultInk)
                views.setTextColor(R.id.widget_trend, defaultInk)
                views.setTextViewText(R.id.widget_glucose_meta, "Libre off")
            }

            views.setTextViewText(R.id.widget_iob, "$iob U ativas")

            when {
                syncing -> {
                    views.setViewVisibility(R.id.widget_status, View.VISIBLE)
                    views.setTextViewText(R.id.widget_status, "Atualizando…")
                }
                lastError.isNotEmpty() -> {
                    views.setViewVisibility(R.id.widget_status, View.VISIBLE)
                    views.setTextViewText(R.id.widget_status, lastError)
                }
                else -> {
                    views.setViewVisibility(R.id.widget_status, View.GONE)
                    views.setTextViewText(R.id.widget_status, "")
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun glucoseColorRes(glucoseMgdl: Int): Int = when {
        glucoseMgdl < 70 -> R.color.widget_glucose_low
        glucoseMgdl > 180 -> R.color.widget_glucose_high
        else -> R.color.widget_glucose_in_range
    }
}
