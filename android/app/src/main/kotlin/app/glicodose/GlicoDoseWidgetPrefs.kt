package app.glicodose

import android.content.Context

object GlicoDoseWidgetPrefs {
    private const val PREFS_NAME = "glicodose_widget_cfg"
    private const val KEY_TRANSPARENT_PREFIX = "transparent_"

    fun isTransparent(context: Context, appWidgetId: Int): Boolean =
        prefs(context).getBoolean(KEY_TRANSPARENT_PREFIX + appWidgetId, false)

    fun setTransparent(context: Context, appWidgetId: Int, transparent: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_TRANSPARENT_PREFIX + appWidgetId, transparent)
            .apply()
    }

    fun clear(context: Context, appWidgetIds: IntArray) {
        val editor = prefs(context).edit()
        for (id in appWidgetIds) {
            editor.remove(KEY_TRANSPARENT_PREFIX + id)
        }
        editor.apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
