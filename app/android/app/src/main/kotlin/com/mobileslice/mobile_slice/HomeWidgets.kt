package com.mobileslice.mobile_slice

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

// Text the app last pushed for the home screen widgets. The widgets only show these
// strings; the app formats them, so the widgets stay correct after the app is closed.
object WidgetData {
    private const val PREFS = "home_widgets"

    fun save(context: Context, values: Map<String, Any?>) {
        val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for ((key, value) in values) {
            if (value == null) editor.remove(key) else editor.putString(key, value.toString())
        }
        editor.apply()
    }

    fun get(context: Context, key: String): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, null) ?: ""

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (provider in listOf(PrinterWidget::class.java, WorkshopWidget::class.java)) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            val views = if (provider == PrinterWidget::class.java) PrinterWidget.render(context) else WorkshopWidget.render(context)
            manager.updateAppWidget(ids, views)
        }
    }

    fun color(name: String): Int = when (name) {
        "green" -> 0xFF5BD46A.toInt()
        "red" -> 0xFFE8475B.toInt()
        "yellow" -> 0xFFFFD447.toInt()
        "accent" -> 0xFFFF8A3D.toInt()
        "text" -> 0xFFF2EFE6.toInt()
        else -> 0xFF8C8AA8.toInt()
    }

    // Opens the app at [action] (see MainActivity.LAUNCH_ACTIONS).
    fun launch(context: Context, action: String, request: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = MainActivity.ACTION_PREFIX + action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(context, request, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}

class PrinterWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, render(context))
    }

    companion object {
        fun render(context: Context): RemoteViews {
            val d = { key: String -> WidgetData.get(context, key) }
            val views = RemoteViews(context.packageName, R.layout.widget_printer)
            views.setTextViewText(R.id.printer_name, d("p_name").ifEmpty { "Drucker" })
            views.setTextViewText(R.id.printer_state, d("p_state").ifEmpty { "App öffnen" })
            views.setTextColor(R.id.printer_state, WidgetData.color(d("p_state_color")))
            setOptional(views, R.id.printer_job, d("p_job"))
            setOptional(views, R.id.printer_line, d("p_line"))
            setOptional(views, R.id.printer_temps, d("p_temps"))
            setOptional(views, R.id.printer_updated, d("p_updated"))
            val percent = d("p_percent").toIntOrNull()
            if (percent == null) {
                views.setViewVisibility(R.id.printer_progress, View.GONE)
            } else {
                views.setViewVisibility(R.id.printer_progress, View.VISIBLE)
                views.setProgressBar(R.id.printer_progress, 100, percent.coerceIn(0, 100), false)
            }
            views.setOnClickPendingIntent(R.id.printer_root, WidgetData.launch(context, "printer", 1))
            return views
        }

        private fun setOptional(views: RemoteViews, id: Int, text: String) {
            views.setTextViewText(id, text)
            views.setViewVisibility(id, if (text.isEmpty()) View.GONE else View.VISIBLE)
        }
    }
}

class WorkshopWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, render(context))
    }

    companion object {
        fun render(context: Context): RemoteViews {
            val d = { key: String -> WidgetData.get(context, key) }
            val views = RemoteViews(context.packageName, R.layout.widget_workshop)
            views.setTextViewText(R.id.workshop_prints, d("w_prints").ifEmpty { "0" })
            views.setTextViewText(R.id.workshop_grams, d("w_grams").ifEmpty { "0 g" })
            views.setTextViewText(R.id.workshop_hours, d("w_hours").ifEmpty { "0 h" })
            views.setTextViewText(R.id.workshop_trophies, d("w_trophies").ifEmpty { "Trophäen" })
            val next = d("w_next")
            views.setTextViewText(R.id.workshop_next, next)
            views.setViewVisibility(R.id.workshop_next, if (next.isEmpty()) View.GONE else View.VISIBLE)
            views.setOnClickPendingIntent(R.id.workshop_root, WidgetData.launch(context, "home", 2))
            views.setOnClickPendingIntent(R.id.workshop_trophy_row, WidgetData.launch(context, "trophies", 3))
            views.setOnClickPendingIntent(R.id.workshop_open, WidgetData.launch(context, "open_model", 4))
            return views
        }
    }
}
