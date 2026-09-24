package app.glicodose

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.Switch

class GlicoDoseWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.glicodose_widget_configure)

        val transparentSwitch = findViewById<Switch>(R.id.widget_transparent_switch)
        transparentSwitch.isChecked = GlicoDoseWidgetPrefs.isTransparent(this, appWidgetId)

        findViewById<Button>(R.id.widget_configure_confirm).setOnClickListener {
            GlicoDoseWidgetPrefs.setTransparent(
                this,
                appWidgetId,
                transparentSwitch.isChecked,
            )

            // Trigger a full update through HomeWidgetProvider so SharedPreferences
            // from Flutter are applied together with the new appearance pref.
            val updateIntent = Intent(this, GlicoDoseWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
            }
            sendBroadcast(updateIntent)

            val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            setResult(RESULT_OK, result)
            finish()
        }
    }
}
