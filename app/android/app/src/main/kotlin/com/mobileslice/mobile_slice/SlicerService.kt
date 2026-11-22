package com.mobileslice.mobile_slice

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

/** Runs the engine executable as a child process while a foreground notification keeps the app alive. */
class SlicerService : Service() {
    interface Listener {
        fun onProgress(jobId: String, percent: Int, message: String)
        fun onFinished(result: Map<String, Any?>)
    }

    /** One engine run. Profile paths are relative to the bundled profiles folder. */
    data class Job(
        val id: String,
        val type: String,
        val model: File,
        val label: String,
        val outputDir: File,
        val baseName: String,
        val process: String?,
        val filament: String?,
        val overrides: String?,
        val modelId: String?,
        /** Uniform model scale factor; null means 1. */
        val scale: Double? = null,
        /** Plate JSON with several placed objects; replaces [model] and [scale] when set. */
        val plate: File? = null,
    )

    inner class LocalBinder : Binder() {
        val service: SlicerService get() = this@SlicerService
    }

    private val binder = LocalBinder()

    @Volatile
    var isRunning = false
        private set

    @Volatile
    private var process: Process? = null

    @Volatile
    private var cancelled = false

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        return START_NOT_STICKY
    }

    fun start(job: Job, listener: Listener): Boolean {
        if (isRunning) return false
        isRunning = true
        cancelled = false
        startForegroundService(Intent(this, SlicerService::class.java))
        thread(name = "slicer-job") {
            val result = try {
                runEngine(job, listener)
            } catch (e: Exception) {
                mapOf("ok" to false, "jobId" to job.id, "type" to job.type, "label" to job.label,
                    "error" to "App-Fehler: ${e.message}")
            }
            try {
                appendLog(result)
            } catch (_: Exception) {
            }
            process = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            isRunning = false
            listener.onFinished(result)
        }
        return true
    }

    fun cancel(): Boolean {
        val running = process ?: return false
        cancelled = true
        running.destroy()
        return true
    }

    private fun runEngine(job: Job, listener: Listener): Map<String, Any?> {
        val nativeDir = applicationInfo.nativeLibraryDir
        val exe = File(nativeDir, "libslicer_cli.so")
        if (!exe.exists()) {
            return mapOf("ok" to false, "jobId" to job.id, "type" to job.type, "label" to job.label,
                "error" to "Engine fehlt: ${exe.path}")
        }
        val engineData = File(filesDir, ASSET_ROOT)
        val profiles = File(engineData, "profiles")
        job.outputDir.mkdirs()
        val temp = File(cacheDir, "engine-tmp")
        temp.deleteRecursively()
        temp.mkdirs()

        val command = mutableListOf(
            exe.path,
            "--resources", File(engineData, "resources").path,
            "--printer", File(profiles, "printer.json").path,
        )
        if (job.plate != null) {
            command += listOf("--plate", job.plate.path)
        } else {
            command += listOf("--model", job.model.path)
            job.scale?.takeIf { it != 1.0 }?.let { command += listOf("--scale", it.toString()) }
        }
        val outputs = linkedMapOf<String, Any?>()
        if (job.type == "preview") {
            val stl = File(job.outputDir, "preview.stl")
            command += listOf("--preview", stl.path)
            outputs["previewPath"] = stl.path
        } else {
            val gcode = File(job.outputDir, "plate_1.gcode")
            val archive = File(job.outputDir, "${job.baseName}.gcode.3mf")
            command += listOf(
                "--process", File(profiles, job.process ?: "process/0.20.json").path,
                "--filament", File(profiles, job.filament ?: "filament/generic-pla.json").path,
                "--output", gcode.path,
                "--export-3mf", archive.path,
            )
            job.modelId?.let { command += listOf("--model-id", it) }
            job.overrides?.let { command += listOf("--overrides", it) }
            outputs["gcodePath"] = gcode.path
            outputs["archivePath"] = archive.path
        }

        val builder = ProcessBuilder(command).directory(temp).redirectErrorStream(true)
        builder.environment()["LD_LIBRARY_PATH"] = nativeDir
        builder.environment()["TMPDIR"] = temp.path

        val started = SystemClock.elapsedRealtime()
        val running = builder.start()
        process = running
        if (cancelled) running.destroy()
        running.outputStream.close()

        val tail = ArrayDeque<String>()
        var engineResult: JSONObject? = null
        var engineError: String? = null
        var stage = "start"
        val warnings = mutableListOf<String>()
        val memory = MemorySampler()

        val reader = thread(name = "slicer-output") {
            running.inputStream.bufferedReader().forEachLine { line ->
                synchronized(tail) {
                    tail.addLast(line)
                    while (tail.size > MAX_LOG_LINES) tail.removeFirst()
                }
                if (!line.startsWith("@@")) return@forEachLine
                val event = try { JSONObject(line.substring(2)) } catch (_: Exception) { return@forEachLine }
                when {
                    event.has("pid") -> memory.start(event.getInt("pid"))
                    event.has("result") -> engineResult = event.getJSONObject("result")
                    event.has("error") -> engineError = event.getString("error")
                    event.has("warning") -> warnings += event.getString("warning")
                    event.has("progress") -> listener.onProgress(job.id, event.getInt("progress"), event.optString("message"))
                }
                if (event.has("stage")) {
                    stage = event.getString("stage")
                    listener.onProgress(job.id, -1, stage)
                }
            }
        }

        val exitCode = running.waitFor()
        val wallMs = SystemClock.elapsedRealtime() - started
        reader.join(2000)
        memory.stop()

        val res = engineResult
        val ok = exitCode == 0 && res != null && !cancelled
        val engineRssKb = res?.optLong("maxRssKb", 0L) ?: 0L
        val result = linkedMapOf<String, Any?>(
            "ok" to ok,
            "jobId" to job.id,
            "type" to job.type,
            "label" to job.label,
            "cancelled" to cancelled,
            "exitCode" to exitCode,
            "signal" to if (cancelled) null else signalName(exitCode),
            "wallMs" to wallMs,
            "peakRssKb" to maxOf(engineRssKb, memory.peakKb),
            "stage" to stage,
            "warnings" to warnings,
            "error" to when {
                cancelled -> "Abgebrochen"
                ok -> null
                else -> engineError ?: "Engine beendet mit Exit-Code $exitCode"
            },
            "device" to deviceInfo(),
            "timestamp" to SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.GERMANY).format(Date()),
        )
        if (ok) result.putAll(outputs)
        if (res != null) result["engine"] = toMap(res)
        result["output"] = synchronized(tail) { tail.joinToString("\n") }
        temp.deleteRecursively()
        return result
    }

    private fun toValue(value: Any?): Any? = when (value) {
        is JSONObject -> toMap(value)
        is JSONArray -> (0 until value.length()).map { toValue(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }

    private fun toMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { toValue(json.get(it)) }

    private fun deviceInfo(): Map<String, Any?> {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return mapOf(
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "cores" to Runtime.getRuntime().availableProcessors(),
            "totalRamKb" to mem.totalMem / 1024,
            "availRamKb" to mem.availMem / 1024,
        )
    }

    private fun appendLog(result: Map<String, Any?>) {
        val log = logFile(this)
        // Keeps the diagnostics log from growing without bound.
        if (log.length() > MAX_LOG_BYTES) log.writeText(log.readText().takeLast((MAX_LOG_BYTES / 2).toInt()))
        val text = buildString {
            appendLine("===== ${result["type"]} ${result["timestamp"] ?: ""} =====")
            for ((key, value) in result) {
                if (key == "output") continue
                appendLine("$key: $value")
            }
            appendLine("--- Engine-Ausgabe ---")
            appendLine(result["output"]?.toString() ?: "")
            appendLine()
        }
        log.appendText(text)
    }

    private fun startInForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Slicen", NotificationManager.IMPORTANCE_LOW),
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Mobile Slice rechnet …")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private class MemorySampler {
        @Volatile var peakKb = 0L
        @Volatile private var active = true
        private var worker: Thread? = null

        fun start(pid: Int) {
            val status = File("/proc/$pid/status")
            worker = thread(name = "slicer-memory") {
                while (active) {
                    val values = try { parseStatus(status.readText()) } catch (_: Exception) { null }
                    if (values != null) peakKb = maxOf(peakKb, values.first, values.second)
                    Thread.sleep(SAMPLE_MS)
                }
            }
        }

        fun stop() {
            active = false
            worker?.join(1000)
        }
    }

    companion object {
        const val ASSET_ROOT = "engine"
        private const val CHANNEL_ID = "slicer"
        private const val NOTIFICATION_ID = 1
        private const val MAX_LOG_LINES = 400
        private const val MAX_LOG_BYTES = 2L * 1024 * 1024
        private const val SAMPLE_MS = 100L

        fun logFile(context: android.content.Context) = File(context.filesDir, "slice-log.txt")

        @Synchronized
        fun appendEntry(context: android.content.Context, title: String, text: String) {
            val log = logFile(context)
            if (log.length() > MAX_LOG_BYTES) log.writeText(log.readText().takeLast((MAX_LOG_BYTES / 2).toInt()))
            val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.GERMANY).format(Date())
            log.appendText("===== $title $time =====\n$text\n\n")
        }

        // Returns (VmHWM, VmRSS) in kB.
        fun parseStatus(text: String): Pair<Long, Long> {
            fun field(name: String) = Regex("^$name:\\s+(\\d+) kB", RegexOption.MULTILINE)
                .find(text)?.groupValues?.get(1)?.toLong() ?: 0L
            return field("VmHWM") to field("VmRSS")
        }

        fun signalName(exitCode: Int): String? = when (exitCode) {
            128 + 4 -> "SIGILL"
            128 + 6 -> "SIGABRT (Absturz/abort)"
            128 + 7 -> "SIGBUS"
            128 + 9 -> "SIGKILL (vermutlich Speicher voll, vom System beendet)"
            128 + 11 -> "SIGSEGV (Speicherzugriffsfehler)"
            else -> null
        }
    }
}
