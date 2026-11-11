package bd.ac.bu.bu_bus_tracker

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.format.DateFormat
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar

/**
 * The "Next bus" home-screen widget.
 *
 * The app writes a summary of the chosen timetable into its preferences
 * (Flutter's `widget.data`). The widget works out the departures still to
 * come from the clock itself, so it stays right through the day without the
 * app running. The next bus has a live countdown (a Chronometer ticking by
 * itself); an alarm at its departure time moves the list on.
 *
 * Small (2x2): the next buses take turns, sliding up. Medium and wider: the
 * next bus in a card, with the departures after it underneath.
 */
class BusWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
        scheduleNext(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REFRESH, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> refreshAll(context)
        }
    }

    override fun onDisabled(context: Context) {
        alarmManager(context).cancel(refreshIntent(context))
    }

    private data class Departure(
        val route: String,
        val color: Int,
        val from: String,
        val to: String,
        val minutes: Int,
        val vehicles: String,
        val tomorrow: Boolean,
    ) {
        /** Milliseconds since epoch at which it leaves. */
        fun at(): Long {
            val c = Calendar.getInstance()
            if (tomorrow) c.add(Calendar.DAY_OF_YEAR, 1)
            c.set(Calendar.HOUR_OF_DAY, minutes / 60)
            c.set(Calendar.MINUTE, minutes % 60)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
            return c.timeInMillis
        }
    }

    private data class Snapshot(
        val title: String,
        val subtitle: String,
        val live: Int,
        val writtenAt: Long,
        val upcoming: List<Departure>,
    )

    companion object {
        const val ACTION_REFRESH = "bd.ac.bu.bu_bus_tracker.WIDGET_REFRESH"
        private const val PREFS = "FlutterSharedPreferences"
        private const val KEY = "flutter.widget.data"

        /** Live counts older than this are not shown: they would mislead. */
        private const val LIVE_FRESH_MS = 10 * 60 * 1000L

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, BusWidgetProvider::class.java))
            ids.forEach { update(context, manager, it) }
            scheduleNext(context)
        }

        fun count(context: Context): Int =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, BusWidgetProvider::class.java)).size

        private fun read(context: Context): Snapshot? {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
            return try {
                val json = JSONObject(raw)
                val list = json.optJSONArray("departures")
                val all = mutableListOf<Departure>()
                if (list != null) {
                    for (i in 0 until list.length()) {
                        val d = list.getJSONObject(i)
                        all += Departure(
                            route = d.optString("r"),
                            color = parseColor(d.optString("c")),
                            from = d.optString("from"),
                            to = d.optString("to"),
                            minutes = d.optInt("m"),
                            vehicles = d.optString("veh"),
                            tomorrow = false,
                        )
                    }
                }
                val now = Calendar.getInstance()
                val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
                val sorted = all.sortedBy { it.minutes }
                // Still to come today; when today is over, tomorrow's first ones.
                val today = sorted.filter { it.minutes >= nowMinutes }
                val upcoming = if (today.isNotEmpty()) today else sorted.map { it.copy(tomorrow = true) }
                Snapshot(
                    title = json.optString("title"),
                    subtitle = json.optString("subtitle"),
                    live = json.optInt("live"),
                    writtenAt = json.optLong("writtenAt"),
                    upcoming = upcoming,
                )
            } catch (e: Exception) {
                null
            }
        }

        private fun parseColor(hex: String): Int =
            try { Color.parseColor(hex) } catch (e: Exception) { Color.parseColor("#5FD4BC") }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val snapshot = read(context)
            val small = build(context, snapshot, small = true)
            val medium = build(context, snapshot, small = false)
            val views = if (Build.VERSION.SDK_INT >= 31) {
                RemoteViews(mapOf(SizeF(100f, 100f) to small, SizeF(220f, 100f) to medium))
            } else {
                val width = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                if (width in 1..199) small else medium
            }
            manager.updateAppWidget(id, views)
        }

        private fun build(context: Context, snapshot: Snapshot?, small: Boolean): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                if (small) R.layout.widget_bus_small else R.layout.widget_bus_medium,
            )
            views.setOnClickPendingIntent(android.R.id.background, openAppIntent(context))

            val liveFresh = snapshot != null && snapshot.live > 0 &&
                System.currentTimeMillis() - snapshot.writtenAt < LIVE_FRESH_MS
            views.setViewVisibility(R.id.live_pill, if (liveFresh) View.VISIBLE else View.GONE)

            if (!small) {
                views.setOnClickPendingIntent(R.id.refresh, refreshIntent(context))
                views.setTextViewText(R.id.title, snapshot?.title?.ifEmpty { null } ?: "Next bus")
                views.setTextViewText(R.id.subtitle, snapshot?.subtitle ?: "")
                if (liveFresh) {
                    views.setTextViewText(
                        R.id.live_text,
                        if (snapshot!!.live == 1) "1 live" else "${snapshot.live} live",
                    )
                }
            }

            val upcoming = snapshot?.upcoming.orEmpty()
            if (upcoming.isEmpty()) {
                val message = if (snapshot == null) {
                    "Open BU Bus Tracker once to set up this widget."
                } else {
                    "No buses in the timetable for this choice. Change it in the app: Profile → Home-screen widget."
                }
                views.setTextViewText(R.id.empty, message)
                views.setViewVisibility(R.id.empty, View.VISIBLE)
                if (small) {
                    views.setViewVisibility(R.id.flipper, View.GONE)
                } else {
                    views.setViewVisibility(R.id.next_card, View.GONE)
                    views.setViewVisibility(R.id.rows, View.GONE)
                }
                return views
            }
            views.setViewVisibility(R.id.empty, View.GONE)

            if (small) {
                views.setViewVisibility(R.id.flipper, View.VISIBLE)
                views.removeAllViews(R.id.flipper)
                upcoming.take(3).forEach { d ->
                    val item = RemoteViews(context.packageName, R.layout.widget_bus_flip_item)
                    item.setInt(R.id.item_dot, "setColorFilter", d.color)
                    item.setTextViewText(R.id.item_route, d.route)
                    item.setTextViewText(R.id.item_time, time(context, d.minutes))
                    item.setTextViewText(R.id.item_dest, "→ ${d.to.ifEmpty { d.from }}")
                    countdown(item, R.id.item_countdown, R.id.item_when, d)
                    views.addView(R.id.flipper, item)
                }
                return views
            }

            val next = upcoming.first()
            views.setViewVisibility(R.id.next_card, View.VISIBLE)
            views.setInt(R.id.next_dot, "setColorFilter", next.color)
            views.setTextViewText(R.id.next_route, next.route)
            views.setTextViewText(R.id.next_dest, if (next.to.isNotEmpty()) "To ${next.to}" else "From ${next.from}")
            views.setTextViewText(
                R.id.next_vehicles,
                listOf("From ${next.from}", next.vehicles).filter { it.isNotBlank() }.joinToString(" · "),
            )
            views.setTextViewText(R.id.next_time, time(context, next.minutes))
            countdown(views, R.id.next_countdown, R.id.next_when, next)

            views.setViewVisibility(R.id.rows, View.VISIBLE)
            views.removeAllViews(R.id.rows)
            upcoming.drop(1).take(3).forEach { d ->
                val row = RemoteViews(context.packageName, R.layout.widget_bus_row)
                row.setInt(R.id.row_dot, "setColorFilter", d.color)
                row.setTextViewText(R.id.row_route, d.route)
                row.setTextViewText(R.id.row_dest, if (d.to.isNotEmpty()) "To ${d.to}" else "From ${d.from}")
                row.setTextViewText(R.id.row_time, (if (d.tomorrow) "Tmrw " else "") + time(context, d.minutes))
                views.addView(R.id.rows, row)
            }
            return views
        }

        /**
         * Under an hour away: a countdown that ticks on its own ("in 12:04").
         * Further: "in 2 h 5 min", or "Tomorrow".
         */
        private fun countdown(views: RemoteViews, chronoId: Int, textId: Int, d: Departure) {
            val left = d.at() - System.currentTimeMillis()
            if (!d.tomorrow && left in 0 until 60 * 60 * 1000L) {
                views.setViewVisibility(chronoId, View.VISIBLE)
                views.setViewVisibility(textId, View.GONE)
                views.setChronometer(chronoId, SystemClock.elapsedRealtime() + left, "in %s", true)
                views.setChronometerCountDown(chronoId, true)
            } else {
                views.setViewVisibility(chronoId, View.GONE)
                views.setViewVisibility(textId, View.VISIBLE)
                val text = when {
                    d.tomorrow -> "Tomorrow"
                    left < 60_000L -> "Now"
                    else -> {
                        val minutes = (left / 60_000L).toInt()
                        "in ${minutes / 60} h ${minutes % 60} min"
                    }
                }
                views.setTextViewText(textId, text)
            }
        }

        private fun time(context: Context, minutes: Int): String {
            val h = minutes / 60
            val m = minutes % 60
            return if (DateFormat.is24HourFormat(context)) {
                String.format("%02d:%02d", h, m)
            } else {
                val h12 = if (h % 12 == 0) 12 else h % 12
                String.format("%d:%02d %s", h12, m, if (h < 12) "AM" else "PM")
            }
        }

        /** Wakes the widget when the next bus leaves, so the list moves on. */
        private fun scheduleNext(context: Context) {
            val next = read(context)?.upcoming?.firstOrNull()
            val manager = alarmManager(context)
            val pending = refreshIntent(context)
            manager.cancel(pending)
            val at = next?.at()?.plus(5_000L) ?: run {
                // Nothing to wait for: look again after midnight.
                Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, 1)
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 1)
                }.timeInMillis
            }
            // A one-minute window: no exact-alarm permission needed.
            manager.setWindow(AlarmManager.RTC, at, 60_000L, pending)
        }

        private fun alarmManager(context: Context) =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        private fun refreshIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, BusWidgetProvider::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
