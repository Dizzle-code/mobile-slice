package com.mobileslice.mobile_slice

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private var service: SlicerService? = null
    private var pendingPick: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var channelReady = false

    // What the app was opened for (shortcut, widget, shared file); Dart takes it once.
    private var pendingLaunch: Map<String, Any?>? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = (binder as SlicerService.LocalBinder).service
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bindService(Intent(this, SlicerService::class.java), connection, Context.BIND_AUTO_CREATE)
        // A restored activity gets its old intent again; that launch was handled already.
        if (savedInstanceState == null) receive(intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    private fun receive(intent: Intent?) {
        val action = intent?.action ?: return
        if (action.startsWith(ACTION_PREFIX)) {
            val name = action.removePrefix(ACTION_PREFIX)
            if (name in LAUNCH_ACTIONS) deliver(mapOf("type" to "action", "action" to name))
            return
        }
        val uri: Uri? = when (action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        }
        if (uri == null) return
        val mime = intent.type ?: contentResolver.getType(uri)
        thread {
            val launch = try {
                mapOf("type" to "file") + copyModel(uri, mime)
            } catch (e: Exception) {
                mapOf("type" to "error", "message" to (e.message ?: "Datei konnte nicht geöffnet werden"))
            }
            main.post { deliver(launch) }
        }
    }

    private fun deliver(launch: Map<String, Any?>) {
        pendingLaunch = launch
        if (channelReady) channel.invokeMethod("launch", null)
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        unbindService(connection)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_slice/slicer")
        channel.setMethodCallHandler(::handle)
        channelReady = true
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> background(result) { prepareAssets(); deviceSummary() }
            "pickModel" -> pickModel(result)
            "takeLaunch" -> {
                result.success(pendingLaunch)
                pendingLaunch = null
            }
            "openUrl" -> openUrl(call.argument<String>("url"), result)
            "updateWidgets" -> background(result) {
                WidgetData.save(this, call.arguments as? Map<String, Any?> ?: emptyMap())
                WidgetData.updateAll(this)
                null
            }
            "runJob" -> runJob(call, result)
            "cancelJob" -> result.success(service?.cancel() ?: false)
            "shareFile" -> shareFile(call.argument<String>("path"), call.argument<String>("mime"),
                call.argument<String>("title"), result)
            "shareLog" -> shareFile(SlicerService.logFile(this).path, "text/plain", "Diagnose-Log teilen", result)
            "appendLog" -> background(result) {
                SlicerService.appendEntry(this, call.argument<String>("title") ?: "App", call.argument<String>("text") ?: "")
                null
            }
            "clearLog" -> {
                SlicerService.logFile(this).delete()
                result.success(null)
            }
            "multicastLock" -> {
                setMulticast(call.argument<Boolean>("on") == true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun runJob(call: MethodCall, result: MethodChannel.Result) {
        val svc = service
        if (svc == null) {
            result.error("unavailable", "Dienst noch nicht bereit", null)
            return
        }
        val job = try {
            SlicerService.Job(
                id = call.argument<String>("jobId")!!,
                type = call.argument<String>("type")!!,
                model = File(call.argument<String>("model")!!),
                label = call.argument<String>("label") ?: "Modell",
                outputDir = File(call.argument<String>("outputDir")!!),
                baseName = safeName(call.argument<String>("baseName") ?: "modell"),
                process = call.argument<String>("process"),
                filament = call.argument<String>("filament"),
                overrides = call.argument<String>("overrides"),
                modelId = call.argument<String>("modelId"),
                scale = call.argument<Double>("scale"),
            )
        } catch (e: NullPointerException) {
            result.error("invalid", "Unvollständiger Auftrag", null)
            return
        }
        // Profiles and outputs must stay inside the app's own storage.
        val profiles = File(filesDir, SlicerService.ASSET_ROOT).canonicalFile
        val allowedProfile = listOfNotNull(job.process, job.filament).all {
            File(File(profiles, "profiles"), it).canonicalPath.startsWith(profiles.path + File.separator)
        }
        if (!allowedProfile || !job.outputDir.canonicalPath.startsWith(filesDir.canonicalPath + File.separator)) {
            result.error("invalid", "Ungültiger Pfad im Auftrag", null)
            return
        }
        val started = svc.start(job, object : SlicerService.Listener {
            override fun onProgress(jobId: String, percent: Int, message: String) {
                main.post {
                    channel.invokeMethod("progress", mapOf("jobId" to jobId, "percent" to percent, "message" to message))
                }
            }

            override fun onFinished(result: Map<String, Any?>) {
                main.post { channel.invokeMethod("finished", result) }
            }
        })
        if (started) result.success(true) else result.error("busy", "Die Engine rechnet bereits", null)
    }

    private fun pickModel(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("model/stl", "model/3mf", "application/sla",
                "application/vnd.ms-pki.stl", "application/vnd.ms-package.3dmanufacturing-3dmodel+xml",
                "application/octet-stream", "application/zip"))
        }
        startActivityForResult(intent, PICK_REQUEST)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        background(result) { copyModel(uri, contentResolver.getType(uri)) }
    }

    // Copies a picked or shared model into app storage; names without .stl/.3mf are guessed from type and content.
    private fun copyModel(uri: Uri, mime: String?): Map<String, Any?> {
        val shown = try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
        } catch (e: Exception) {
            null
        } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "modell"
        val dir = File(filesDir, "models").apply { mkdirs() }
        val target = File(dir, "${System.currentTimeMillis()}_${safeName(shown)}")
        val input = contentResolver.openInputStream(uri) ?: throw IllegalArgumentException("Datei nicht lesbar")
        input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
        val name = modelName(shown, mime, target)
        if (name == null) {
            target.delete()
            throw IllegalArgumentException("Bitte eine .stl- oder .3mf-Datei wählen (gewählt: $shown)")
        }
        val finalFile = if (name == shown) target else File(dir, "${System.currentTimeMillis()}_${safeName(name)}").also { target.renameTo(it) }
        return mapOf("path" to finalFile.path, "name" to name, "bytes" to finalFile.length())
    }

    private fun modelName(shown: String, mime: String?, file: File): String? {
        val lower = shown.lowercase()
        // Sliced Bambu files also end in .3mf but hold G-code, not a model.
        if (lower.endsWith(".gcode.3mf")) return null
        if (lower.endsWith(".stl") || lower.endsWith(".3mf")) return shown
        val head = ByteArray(2)
        val read = file.inputStream().use { it.read(head) }
        val zip = read == 2 && head[0] == 'P'.code.toByte() && head[1] == 'K'.code.toByte()
        val type = mime?.lowercase() ?: ""
        return when {
            zip && ("3mf" in type || "3dmanufacturing" in type || type == "application/octet-stream") -> "$shown.3mf"
            !zip && ("stl" in type || "sla" in type) -> "$shown.stl"
            else -> null
        }
    }

    // Only web pages; the browser decides how to show them.
    private fun openUrl(url: String?, result: MethodChannel.Result) {
        val uri = url?.let { Uri.parse(it) }
        if (uri == null || uri.scheme != "https") {
            result.error("invalid", "Nur https-Adressen", null)
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
            result.success(true)
        } catch (e: android.content.ActivityNotFoundException) {
            result.error("no_browser", "Kein Browser gefunden", null)
        }
    }

    private fun shareFile(path: String?, mime: String?, title: String?, result: MethodChannel.Result) {
        val file = path?.let { File(it) }
        if (file == null || !file.exists() || file.length() == 0L) {
            result.error("empty", "Datei nicht vorhanden", null)
            return
        }
        if (!file.canonicalPath.startsWith(filesDir.canonicalPath + File.separator)) {
            result.error("invalid", "Nur App-Dateien können geteilt werden", null)
            return
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.logs", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime ?: "application/octet-stream"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, file.name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(send, title ?: "Teilen"))
        result.success(true)
    }

    // SSDP discovery only receives multicast while this lock is held.
    private fun setMulticast(on: Boolean) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = multicastLock ?: wifi.createMulticastLock("mobile-slice-ssdp").also {
            it.setReferenceCounted(false)
            multicastLock = it
        }
        if (on && !lock.isHeld) lock.acquire()
        if (!on && lock.isHeld) lock.release()
    }

    // Copies the bundled engine data once per installed app version.
    private fun prepareAssets() {
        val root = File(filesDir, SlicerService.ASSET_ROOT)
        val stamp = File(root, ".version")
        val version = packageManager.getPackageInfo(packageName, 0).lastUpdateTime.toString()
        if (stamp.exists() && stamp.readText() == version) return
        root.deleteRecursively()
        val loader = FlutterInjector.instance().flutterLoader()
        copyAssetDir(loader.getLookupKeyForAsset("assets/engine"), root)
        stamp.writeText(version)
    }

    private fun copyAssetDir(assetPath: String, target: File) {
        val children = assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            target.parentFile?.mkdirs()
            assets.open(assetPath).use { input -> target.outputStream().use { input.copyTo(it) } }
            return
        }
        target.mkdirs()
        for (child in children) copyAssetDir("$assetPath/$child", File(target, child))
    }

    private fun deviceSummary(): Map<String, Any?> = mapOf(
        "appDir" to filesDir.path,
        "engineDir" to File(filesDir, SlicerService.ASSET_ROOT).path,
        "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
        "android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
        "cores" to Runtime.getRuntime().availableProcessors(),
        "engineInstalled" to File(applicationInfo.nativeLibraryDir, "libslicer_cli.so").exists(),
    )

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        thread {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        private const val PICK_REQUEST = 4711
        const val ACTION_PREFIX = "com.mobileslice.mobile_slice.launch."
        val LAUNCH_ACTIONS = setOf("home", "open_model", "printer", "history", "trophies")

        fun safeName(name: String): String =
            name.replace(Regex("[^A-Za-z0-9._ -]"), "_").trim().take(80).ifEmpty { "modell" }
    }
}
