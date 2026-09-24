package app.glicodose

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.util.TypedValue
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

            val transparent = GlicoDoseWidgetPrefs.isTransparent(context, widgetId)
            if (transparent) {
                views.setInt(R.id.widget_root, "setBackgroundResource", 0)
                views.setInt(R.id.widget_root, "setBackgroundColor", android.graphics.Color.TRANSPARENT)
            } else {
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundResource",
                    R.drawable.glicodose_widget_background,
                )
            }

            val chrome = if (transparent) {
                systemAccentColor(context)
            } else {
                ContextCompat.getColor(context, R.color.widget_primary)
            }
            views.setTextColor(R.id.widget_title, chrome)
            views.setInt(R.id.widget_sync, "setColorFilter", chrome)

            val defaultInk = ContextCompat.getColor(context, R.color.widget_ink)
            val muted = ContextCompat.getColor(context, R.color.widget_muted)

            val connected = widgetData.getBoolean("libre_connected", false)
            val hasGlucose = widgetData.getBoolean("has_glucose", false)
            val glucose = widgetData.getInt("glucose_mgdl", 0)
            val trend = widgetData.getString("trend_label", "").orEmpty()
            val age = widgetData.getString("glucose_age", "").orEmpty()
            val iob = widgetData.getInt("iob_u", 0)
            val syncing = widgetData.getBoolean("syncing", false)
            val lastError = widgetData.getString("last_error", "").orEmpty()

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

            views.setTextColor(R.id.widget_glucose_meta, muted)
            views.setTextViewText(R.id.widget_iob, "$iob U ativas")
            views.setTextColor(R.id.widget_iob, defaultInk)
            views.setTextColor(R.id.widget_status, muted)

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

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        GlicoDoseWidgetPrefs.clear(context, appWidgetIds)
    }

    private fun systemAccentColor(context: Context): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return context.getColor(android.R.color.system_accent1_600)
        }
        val typedValue = TypedValue()
        val theme = context.theme
        if (theme.resolveAttribute(android.R.attr.colorAccent, typedValue, true)) {
            return if (typedValue.resourceId != 0) {
                ContextCompat.getColor(context, typedValue.resourceId)
            } else {
                typedValue.data
            }
        }
        if (theme.resolveAttribute(android.R.attr.colorPrimary, typedValue, true)) {
            return if (typedValue.resourceId != 0) {
                ContextCompat.getColor(context, typedValue.resourceId)
            } else {
                typedValue.data
            }
        }
        return ContextCompat.getColor(context, R.color.widget_primary)
    }

    private fun glucoseColorRes(glucoseMgdl: Int): Int = when {
        glucoseMgdl < 70 -> R.color.widget_glucose_low
        glucoseMgdl > 180 -> R.color.widget_glucose_high
        else -> R.color.widget_glucose_in_range
    }
}
