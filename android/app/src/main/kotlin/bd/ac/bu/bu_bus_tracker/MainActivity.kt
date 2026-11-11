package bd.ac.bu.bu_bus_tracker

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Installs app updates from inside the app.
 *
 * The downloaded APK is written into an Android PackageInstaller session;
 * Android then shows its own "update this app?" confirmation, which every
 * app installed outside a store must show. The result comes back to
 * [onNewIntent] and is passed to Dart as "installStatus".
 *
 * Also opens links in the browser for the About page ("openUrl").
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "appInfo" -> result.success(appInfo())
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "No file given", null)
                        } else {
                            // Copying a large file into the session is done off the UI thread.
                            Thread {
                                try {
                                    install(File(path))
                                    runOnUiThread { result.success(null) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("install_failed", e.message, null) }
                                }
                            }.start()
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null || !url.startsWith("https://")) {
                            result.error("bad_args", "Only https links", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("no_browser", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun appInfo(): Map<String, Any?> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
        val code = if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to info.versionName,
            "versionCode" to code,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /** Android 8+ asks once per app before it may install APKs. */
    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT >= 26) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
            )
        }
    }

    private fun install(apk: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("update.apk", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val status = Intent(this, MainActivity::class.java).setAction(ACTION_INSTALL_STATUS)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getActivity(this, sessionId, status, flags)
            session.commit(pending.intentSender)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != ACTION_INSTALL_STATUS) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            if (confirm != null) startActivity(confirm)
            channel?.invokeMethod("installStatus", mapOf("status" to "confirm"))
            return
        }
        val name = when (status) {
            PackageInstaller.STATUS_SUCCESS -> "success"
            PackageInstaller.STATUS_FAILURE_ABORTED -> "aborted"
            PackageInstaller.STATUS_FAILURE_CONFLICT -> "conflict"
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "incompatible"
            PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
            PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
            PackageInstaller.STATUS_FAILURE_INVALID -> "invalid"
            else -> "failure"
        }
        channel?.invokeMethod(
            "installStatus",
            mapOf("status" to name, "message" to intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)),
        )
    }

    companion object {
        const val CHANNEL = "bd.ac.bu.bu_bus_tracker/app_update"
        const val ACTION_INSTALL_STATUS = "bd.ac.bu.bu_bus_tracker.INSTALL_STATUS"
    }
}
