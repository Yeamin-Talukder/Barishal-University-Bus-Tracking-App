package bd.ac.bu.bu_bus_tracker

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The settings screen of one "Next bus" widget: which buses it shows.
 *
 * Opened by the launcher (long-press the widget, then Settings; or when the
 * widget is added on Android 11 and older) and by tapping the widget's
 * title. It runs the Dart entry point `widgetConfigMain`, a small app of
 * its own, so it does not start the whole tracker. Saving stores the
 * choice for this widget only and redraws it.
 */
class WidgetConfigActivity : FlutterActivity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        widgetId = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Leaving without saving must not add a widget the launcher asked about.
        setResult(Activity.RESULT_CANCELED, resultData())
        super.onCreate(savedInstanceState)
    }

    override fun getDartEntrypointFunctionName(): String = "widgetConfigMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "target" -> {
                    if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID || !BusWidgetProvider.isOurs(this, widgetId)) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf("id" to widgetId, "choice" to BusWidgetProvider.savedChoice(this, widgetId)),
                        )
                    }
                }
                "save" -> {
                    val json = call.argument<String>("choice")
                    if (json == null || widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
                        result.error("bad_args", "Nothing to save", null)
                    } else {
                        BusWidgetProvider.setChoice(this, widgetId, json)
                        setResult(Activity.RESULT_OK, resultData())
                        result.success(null)
                        finish()
                    }
                }
                "cancel" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun resultData() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

    companion object {
        const val CHANNEL = "bd.ac.bu.bu_bus_tracker/widget_config"
    }
}
