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
 * The app writes the whole timetable into its preferences (Flutter's
 * `widget.timetable`). Every widget on the home screen has its own choice
 * (who for, which route, which way), kept here in [WIDGET_PREFS]; a new
 * widget starts with the choice set up in the app's Profile. The widget
 * works out the departures still to come from the clock itself, so it
 * stays right through the day without the app running. The next bus has a
 * live countdown (a Chronometer ticking by itself); an alarm at each
 * departure time moves the list on.
 *
 * Bus names come first: passengers find their bus by the name on it.
 * Tapping a departure opens its route in the app; tapping the title opens
 * this widget's settings.
 *
 * Small (2x2): the next buses take turns, sliding up. Medium and wider: the
 * next bus in a card, with the departures after it underneath.
 */
class BusWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val timetable = read(context)
        ids.forEach { update(context, manager, it, timetable) }
        scheduleNext(context, timetable)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id, read(context))
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val editor = widgetPrefs(context).edit()
        ids.forEach { editor.remove(choiceKey(it)) }
        editor.apply()
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
        val group: String,
        val route: String,
        val color: Int,
        val from: String,
        val to: String,
        val minutes: Int,
        val vehicles: String,
        val towardsCampus: Boolean,
        val fromCampus: Boolean,
    ) {
        /** What tells a passenger which bus to get on. */
        val headline: String get() = vehicles.ifBlank { "Route $route" }
    }

    private data class Upcoming(val departure: Departure, val tomorrow: Boolean) {
        /** Milliseconds since epoch at which it leaves. */
        fun at(): Long {
            val c = Calendar.getInstance()
            if (tomorrow) c.add(Calendar.DAY_OF_YEAR, 1)
            c.set(Calendar.HOUR_OF_DAY, departure.minutes / 60)
            c.set(Calendar.MINUTE, departure.minutes % 60)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
            return c.timeInMillis
        }
    }

    private data class Timetable(
        val groups: Map<String, String>,
        val departures: List<Departure>,
        val live: Map<String, Int>,
        val writtenAt: Long,
    )

    private data class Choice(val group: String, val route: String, val direction: String) {
        fun matches(d: Departure): Boolean =
            d.group == group &&
                (route == ALL_ROUTES || d.route == route) &&
                when (direction) {
                    "toUniversity" -> d.towardsCampus
                    "fromUniversity" -> d.fromCampus
                    else -> true
                }

        val directionLabel: String
            get() = when (direction) {
                "toUniversity" -> "To campus"
                "fromUniversity" -> "From campus"
                else -> "Both ways"
            }

        fun toJson(): String =
            JSONObject().put("group", group).put("route", route).put("direction", direction).toString()

        companion object {
            fun parse(raw: String?): Choice? = try {
                if (raw == null) null else JSONObject(raw).let {
                    Choice(
                        it.optString("group", "student"),
                        it.optString("route", ALL_ROUTES),
                        it.optString("direction", "both"),
                    )
                }
            } catch (e: Exception) {
                null
            }
        }
    }

    /** Where the day stands for one widget. */
    private class Day(val upcoming: List<Upcoming>, val leftToday: Int) {
        val isOver: Boolean get() = leftToday == 0 && upcoming.isNotEmpty()
        val lastToday: Departure? get() = if (leftToday == 0) null else upcoming[leftToday - 1].departure
        val nextLabel: String
            get() = when {
                isOver -> "No more buses today"
                leftToday == 1 -> "Last bus today"
                else -> "Next bus"
            }

        companion object {
            /** Today's still to come, then tomorrow's first ones to fill the list. */
            fun of(departures: List<Departure>, count: Int = 4): Day {
                val now = Calendar.getInstance()
                val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
                val today = departures.filter { it.minutes >= nowMinutes }
                val shown = today.take(count).map { Upcoming(it, false) }
                val tomorrow = departures.take(count - shown.size).map { Upcoming(it, true) }
                return Day(shown + tomorrow, today.size)
            }
        }
    }

    companion object {
        const val ACTION_REFRESH = "bd.ac.bu.bu_bus_tracker.WIDGET_REFRESH"
        const val ACTION_OPEN_DEPARTURE = "bd.ac.bu.bu_bus_tracker.OPEN_DEPARTURE"
        const val EXTRA_ROUTE = "route"
        const val EXTRA_FROM = "from"
        const val EXTRA_MINUTES = "minutes"

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val TIMETABLE_KEY = "flutter.widget.timetable"
        private const val DEFAULT_CHOICE_KEY = "flutter.widget.choice"
        private const val WIDGET_PREFS = "bus_widget"
        private const val ALL_ROUTES = "all"

        /** Live counts older than this are not shown: they would mislead. */
        private const val LIVE_FRESH_MS = 10 * 60 * 1000L

        private fun widgetPrefs(context: Context) =
            context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)

        private fun choiceKey(id: Int) = "choice.$id"

        private fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, BusWidgetProvider::class.java))

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val timetable = read(context)
            ids(context).forEach { update(context, manager, it, timetable) }
            scheduleNext(context, timetable)
        }

        fun isOurs(context: Context, id: Int): Boolean = ids(context).contains(id)

        /** Every placed widget with its choice, as JSON, for the app's Profile. */
        fun placed(context: Context): List<Map<String, Any>> =
            ids(context).map { mapOf("id" to it, "choice" to choiceOf(context, it).toJson()) }

        /** The saved choice of a widget, as JSON; null for a widget not set up yet. */
        fun savedChoice(context: Context, id: Int): String? = widgetPrefs(context).getString(choiceKey(id), null)

        fun setChoice(context: Context, id: Int, json: String) {
            val choice = Choice.parse(json) ?: return
            widgetPrefs(context).edit().putString(choiceKey(id), choice.toJson()).apply()
            val timetable = read(context)
            update(context, AppWidgetManager.getInstance(context), id, timetable)
            scheduleNext(context, timetable)
        }

        /**
         * A widget's choice. One placed before it had its own takes the one
         * set up in the app (what every widget showed until then) and keeps
         * it from then on.
         */
        private fun choiceOf(context: Context, id: Int): Choice {
            Choice.parse(savedChoice(context, id))?.let { return it }
            val fallback = Choice.parse(
                context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).getString(DEFAULT_CHOICE_KEY, null),
            ) ?: Choice("student", ALL_ROUTES, "both")
            widgetPrefs(context).edit().putString(choiceKey(id), fallback.toJson()).apply()
            return fallback
        }

        private fun read(context: Context): Timetable? {
            val raw = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(TIMETABLE_KEY, null) ?: return null
            return try {
                val json = JSONObject(raw)
                val groups = linkedMapOf<String, String>()
                json.optJSONArray("groups")?.let { list ->
                    for (i in 0 until list.length()) {
                        val g = list.getJSONObject(i)
                        groups[g.optString("id")] = g.optString("name")
                    }
                }
                val departures = mutableListOf<Departure>()
                json.optJSONArray("departures")?.let { list ->
                    for (i in 0 until list.length()) {
                        val d = list.getJSONObject(i)
                        departures += Departure(
                            group = d.optString("g"),
                            route = d.optString("r"),
                            color = parseColor(d.optString("c")),
                            from = d.optString("from"),
                            to = d.optString("to"),
                            minutes = d.optInt("m"),
                            vehicles = d.optString("veh"),
                            towardsCampus = d.optBoolean("tc"),
                            fromCampus = d.optBoolean("fc"),
                        )
                    }
                }
                val live = mutableMapOf<String, Int>()
                json.optJSONObject("live")?.let { o -> o.keys().forEach { live[it] = o.optInt(it) } }
                Timetable(groups, departures.sortedBy { it.minutes }, live, json.optLong("writtenAt"))
            } catch (e: Exception) {
                null
            }
        }

        private fun parseColor(hex: String): Int =
            try { Color.parseColor(hex) } catch (e: Exception) { Color.parseColor("#5FD4BC") }

        private fun update(context: Context, manager: AppWidgetManager, id: Int, timetable: Timetable?) {
            val choice = choiceOf(context, id)
            val small = build(context, id, timetable, choice, small = true)
            val medium = build(context, id, timetable, choice, small = false)
            val views = if (Build.VERSION.SDK_INT >= 31) {
                RemoteViews(mapOf(SizeF(100f, 100f) to small, SizeF(220f, 100f) to medium))
            } else {
                val width = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                if (width in 1..199) small else medium
            }
            manager.updateAppWidget(id, views)
        }

        private fun build(
            context: Context,
            id: Int,
            timetable: Timetable?,
            choice: Choice,
            small: Boolean,
        ): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                if (small) R.layout.widget_bus_small else R.layout.widget_bus_medium,
            )
            views.setOnClickPendingIntent(android.R.id.background, openAppIntent(context))

            val departures = timetable?.departures.orEmpty().filter { choice.matches(it) }
            val day = Day.of(departures)
            val live = when {
                timetable == null -> 0
                System.currentTimeMillis() - timetable.writtenAt >= LIVE_FRESH_MS -> 0
                choice.route == ALL_ROUTES -> timetable.live.values.sum()
                else -> timetable.live[choice.route] ?: 0
            }
            views.setViewVisibility(R.id.live_pill, if (live > 0) View.VISIBLE else View.GONE)

            if (!small) {
                views.setOnClickPendingIntent(R.id.refresh, refreshIntent(context))
                views.setOnClickPendingIntent(R.id.header, settingsIntent(context, id))
                val group = timetable?.groups?.get(choice.group)?.ifBlank { null }
                    ?: choice.group.replaceFirstChar { it.uppercase() }
                val route = if (choice.route == ALL_ROUTES) "All routes" else "Route ${choice.route}"
                views.setTextViewText(R.id.title, "$group · $route")
                val last = day.lastToday
                views.setTextViewText(
                    R.id.subtitle,
                    if (last != null && day.leftToday > 1) {
                        "${choice.directionLabel} · last bus ${time(context, last.minutes)}"
                    } else {
                        choice.directionLabel
                    },
                )
                if (live > 0) views.setTextViewText(R.id.live_text, "$live live")
            }

            val upcoming = day.upcoming
            if (upcoming.isEmpty()) {
                val message = if (timetable == null) {
                    "Open BU Bus Tracker once to set up this widget."
                } else {
                    "No buses in the timetable for this choice. Tap to change it."
                }
                views.setTextViewText(R.id.empty, message)
                views.setViewVisibility(R.id.empty, View.VISIBLE)
                views.setOnClickPendingIntent(R.id.empty, settingsIntent(context, id))
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
                upcoming.take(3).forEachIndexed { index, u ->
                    val d = u.departure
                    val item = RemoteViews(context.packageName, R.layout.widget_bus_flip_item)
                    item.setInt(R.id.item_dot, "setColorFilter", d.color)
                    item.setTextViewText(R.id.item_route, d.route)
                    item.setTextViewText(R.id.item_name, d.headline)
                    item.setTextViewText(R.id.item_time, time(context, d.minutes))
                    item.setTextViewText(R.id.item_dest, "→ ${d.to.ifEmpty { d.from }}")
                    val tag = when {
                        u.tomorrow && index == 0 -> "No more today"
                        !u.tomorrow && index == day.leftToday - 1 -> "Last today"
                        else -> null
                    }
                    item.setViewVisibility(R.id.item_tag, if (tag != null) View.VISIBLE else View.GONE)
                    if (tag != null) item.setTextViewText(R.id.item_tag, tag)
                    countdown(item, R.id.item_countdown, R.id.item_when, u)
                    item.setOnClickPendingIntent(R.id.item_root, departureIntent(context, d))
                    views.addView(R.id.flipper, item)
                }
                return views
            }

            val next = upcoming.first()
            val d = next.departure
            views.setViewVisibility(R.id.next_card, View.VISIBLE)
            // Two labels, so each keeps its colour when the phone switches
            // between light and dark.
            val warn = day.leftToday <= 1
            views.setViewVisibility(R.id.next_label, if (warn) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.next_label_warn, if (warn) View.VISIBLE else View.GONE)
            views.setTextViewText(if (warn) R.id.next_label_warn else R.id.next_label, day.nextLabel.uppercase())
            views.setInt(R.id.next_dot, "setColorFilter", d.color)
            views.setTextViewText(R.id.next_route, d.route)
            views.setTextViewText(R.id.next_name, d.headline)
            views.setTextViewText(
                R.id.next_where,
                listOf(
                    if (d.to.isNotEmpty()) "To ${d.to}" else "",
                    if (d.from.isNotEmpty()) "from ${d.from}" else "",
                ).filter { it.isNotEmpty() }.joinToString(" · "),
            )
            views.setTextViewText(R.id.next_time, time(context, d.minutes))
            countdown(views, R.id.next_countdown, R.id.next_when, next)
            views.setOnClickPendingIntent(R.id.next_card, departureIntent(context, d))

            views.setViewVisibility(R.id.rows, View.VISIBLE)
            views.removeAllViews(R.id.rows)
            upcoming.drop(1).take(3).forEach { u ->
                val r = u.departure
                val row = RemoteViews(context.packageName, R.layout.widget_bus_row)
                row.setInt(R.id.row_dot, "setColorFilter", r.color)
                row.setTextViewText(R.id.row_route, r.route)
                row.setTextViewText(R.id.row_name, r.headline)
                row.setTextViewText(R.id.row_dest, "→ ${r.to.ifEmpty { r.from }}")
                row.setTextViewText(R.id.row_time, (if (u.tomorrow) "Tmrw " else "") + time(context, r.minutes))
                row.setOnClickPendingIntent(R.id.row_root, departureIntent(context, r))
                views.addView(R.id.rows, row)
            }
            return views
        }

        /**
         * Under an hour away: a countdown that ticks on its own ("in 12:04").
         * Further: "in 2 h 5 min", or "Tomorrow".
         */
        private fun countdown(views: RemoteViews, chronoId: Int, textId: Int, u: Upcoming) {
            val left = u.at() - System.currentTimeMillis()
            if (!u.tomorrow && left in 0 until 60 * 60 * 1000L) {
                views.setViewVisibility(chronoId, View.VISIBLE)
                views.setViewVisibility(textId, View.GONE)
                views.setChronometer(chronoId, SystemClock.elapsedRealtime() + left, "in %s", true)
                views.setChronometerCountDown(chronoId, true)
            } else {
                views.setViewVisibility(chronoId, View.GONE)
                views.setViewVisibility(textId, View.VISIBLE)
                val text = when {
                    u.tomorrow -> "Tomorrow"
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

        /**
         * Wakes the widgets when the next bus of any of them leaves, so their
         * lists move on.
         */
        private fun scheduleNext(context: Context, timetable: Timetable?) {
            val choices = ids(context).map { choiceOf(context, it) }
            val next = choices
                .mapNotNull { c -> Day.of(timetable?.departures.orEmpty().filter { c.matches(it) }).upcoming.firstOrNull() }
                .minByOrNull { it.at() }
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

        /** Opens the app on this departure's route, shown the way it goes. */
        private fun departureIntent(context: Context, d: Departure): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN_DEPARTURE)
                .putExtra(EXTRA_ROUTE, d.route)
                .putExtra(EXTRA_FROM, d.from)
                .putExtra(EXTRA_MINUTES, d.minutes)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            // One request code per departure, so their extras stay apart.
            val code = 1000 + (d.route + "|" + d.from + "|" + d.minutes).hashCode() and 0x3FFFFFFF
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** Opens this widget's settings. */
        private fun settingsIntent(context: Context, id: Int): PendingIntent = PendingIntent.getActivity(
            context,
            2_000_000 + id,
            Intent(context, WidgetConfigActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
