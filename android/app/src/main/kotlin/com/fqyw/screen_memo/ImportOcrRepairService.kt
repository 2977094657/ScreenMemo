package com.fqyw.screen_memo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class ImportOcrRepairService : Service() {

    companion object {
        private const val TAG = "ImportOcrRepairService"
        private const val STATUS_TAG = "IMPORT_DIAG"
        private const val ACTION_START = "com.fqyw.screen_memo.action.START_IMPORT_OCR_REPAIR"
        private const val ACTION_RESUME = "com.fqyw.screen_memo.action.RESUME_IMPORT_OCR_REPAIR"
        private const val ACTION_CANCEL = "com.fqyw.screen_memo.action.CANCEL_IMPORT_OCR_REPAIR"
        private const val EXTRA_ONLY_MISSING = "only_missing"
        private const val EXTRA_BATCH_SIZE = "batch_size"
        private const val NOTIFICATION_ID = 1036
        private const val CHANNEL_ID = "import_ocr_repair_channel"

        fun startOrResumeTask(
            context: Context,
            onlyMissing: Boolean = true,
            batchSize: Int = 12
        ): Map<String, Any?> {
            val current = ImportOcrRepairTaskStore.load(context)
            if (current != null && current.isRecoverable()) {
                startService(context, ACTION_RESUME, current.onlyMissing, current.batchSize)
                return current.toMap()
            }

            val now = System.currentTimeMillis()
            val next = ImportOcrRepairTaskState(
                taskId = "import_ocr_${now}",
                status = ImportOcrRepairTaskState.STATUS_PREPARING,
                onlyMissing = onlyMissing,
                batchSize = batchSize.coerceIn(1, 64),
                startedAt = now,
                updatedAt = now,
                completedAt = 0L,
                candidateRows = 0,
                processedRows = 0,
                updatedRows = 0,
                emptyTextRows = 0,
                failedRows = 0,
                missingFiles = 0,
                currentWorkIndex = 0,
                currentLastId = 0,
                currentPackageName = "",
                currentYear = 0,
                currentTableName = "",
                totalWorks = 0,
                lastError = null,
                warnings = mutableListOf(),
                errors = mutableListOf(),
                works = mutableListOf(),
            )
            ImportOcrRepairTaskStore.save(context, next)
            startService(context, ACTION_START, onlyMissing, next.batchSize)
            return next.toMap()
        }

        fun ensureResumedIfPending(context: Context, reason: String = "manual"): Map<String, Any?> {
            val current = ImportOcrRepairTaskStore.load(context)
            if (current != null && current.isRecoverable()) {
                FileLogger.i(TAG, "检测到未完成 OCR 修复任务，尝试恢复，reason=$reason")
                startService(context, ACTION_RESUME, current.onlyMissing, current.batchSize)
                return current.toMap()
            }
            return current?.toMap() ?: ImportOcrRepairTaskState.idle().toMap()
        }

        fun getTaskStatus(context: Context): Map<String, Any?> {
            return ImportOcrRepairTaskStore.load(context)?.toMap()
                ?: ImportOcrRepairTaskState.idle().toMap()
        }

        fun cancelTask(context: Context): Map<String, Any?> {
            val current = ImportOcrRepairTaskStore.load(context)
            if (current == null) {
                return ImportOcrRepairTaskState.idle().toMap()
            }
            current.status = ImportOcrRepairTaskState.STATUS_CANCELLED
            current.completedAt = System.currentTimeMillis()
            current.updatedAt = current.completedAt
            ImportOcrRepairTaskStore.save(context, current)
            startService(context, ACTION_CANCEL, current.onlyMissing, current.batchSize)
            return current.toMap()
        }

        private fun startService(
            context: Context,
            action: String,
            onlyMissing: Boolean,
            batchSize: Int
        ) {
            val intent = Intent(context, ImportOcrRepairService::class.java).apply {
                this.action = action
                putExtra(EXTRA_ONLY_MISSING, onlyMissing)
                putExtra(EXTRA_BATCH_SIZE, batchSize)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "启动 ImportOcrRepairService 失败", e)
            }
        }
    }

    private val workerExecutor = Executors.newSingleThreadExecutor()
    private val workerStarted = AtomicBoolean(false)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_RESUME
        if (action == ACTION_CANCEL) {
            return START_NOT_STICKY
        }

        val state = ImportOcrRepairTaskStore.load(this)
        if (state == null || !state.isRecoverable()) {
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForeground(state)
        if (workerStarted.compareAndSet(false, true)) {
            workerExecutor.execute { runWorker() }
        } else {
            updateNotification(state)
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        FileLogger.i(TAG, "宿主任务被移除，OCR 修复服务继续运行")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        try {
            workerExecutor.shutdownNow()
        } catch (_: Exception) {}
        releaseWakeLock()
        workerStarted.set(false)
        super.onDestroy()
    }

    private fun runWorker() {
        acquireWakeLock()
        var finalState: ImportOcrRepairTaskState? = null
        try {
            var state = ImportOcrRepairTaskStore.load(this) ?: return
            if (state.status == ImportOcrRepairTaskState.STATUS_CANCELLED) {
                finalState = state
                return
            }

            if (!state.hasPreparedWorks()) {
                state = prepareWorkItems(state)
            }
            if (!state.isRecoverable()) {
                finalState = state
                return
            }

            state.status = ImportOcrRepairTaskState.STATUS_RUNNING
            state.updatedAt = System.currentTimeMillis()
            ImportOcrRepairTaskStore.save(this, state)
            updateNotification(state)

            finalState = processPreparedWorks(state)
        } catch (e: Exception) {
            val failed = ImportOcrRepairTaskStore.load(this) ?: ImportOcrRepairTaskState.idle()
            failed.status = ImportOcrRepairTaskState.STATUS_FAILED
            failed.lastError = e.message ?: e.toString()
            failed.completedAt = System.currentTimeMillis()
            failed.updatedAt = failed.completedAt
            failed.appendError("OCR 修复失败: ${failed.lastError}")
            ImportOcrRepairTaskStore.save(this, failed)
            FileLogger.e(TAG, "OCR 修复服务执行失败", e)
            finalState = failed
        } finally {
            workerStarted.set(false)
            releaseWakeLock()
            if (finalState != null) {
                finishTask(finalState!!)
            } else {
                stopSelf()
            }
        }
    }

    private fun prepareWorkItems(state: ImportOcrRepairTaskState): ImportOcrRepairTaskState {
        state.status = ImportOcrRepairTaskState.STATUS_PREPARING
        state.updatedAt = System.currentTimeMillis()
        ImportOcrRepairTaskStore.save(this, state)
        updateNotification(state)

        var masterDb: SQLiteDatabase? = null
        try {
            val masterPath = ScreenshotDatabaseHelper.resolveMasterDbPath(this)
                ?: throw IllegalStateException("主库路径不可用")
            masterDb = SQLiteDatabase.openDatabase(
                masterPath,
                null,
                SQLiteDatabase.OPEN_READONLY,
            )
            val works = ArrayList<ImportOcrRepairWorkItem>()
            var candidateRows = 0
            masterDb.query(
                "shard_registry",
                arrayOf("app_package_name", "year", "db_path"),
                null,
                null,
                null,
                null,
                "app_package_name ASC, year ASC",
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val packageName = cursor.getStringOrNull(0)?.trim().orEmpty()
                    val year = cursor.getIntOrNull(1) ?: continue
                    val registryDbPath = cursor.getStringOrNull(2)
                    if (packageName.isEmpty()) continue
                    val resolvedDbPath = ScreenshotDatabaseHelper.resolveExistingShardDbPath(
                        this,
                        packageName,
                        year,
                        registryDbPath,
                    )
                    if (resolvedDbPath.isNullOrBlank()) {
                        state.appendWarning("分库不存在: $packageName/$year")
                        continue
                    }
                    var shardDb: SQLiteDatabase? = null
                    try {
                        shardDb = SQLiteDatabase.openDatabase(
                            resolvedDbPath,
                            null,
                            SQLiteDatabase.OPEN_READONLY,
                        )
                        for (month in 1..12) {
                            val tableName = monthTableName(year, month)
                            if (!tableExists(shardDb, tableName)) continue
                            val count = countCandidateRows(shardDb, tableName, state.onlyMissing)
                            if (count <= 0) continue
                            works.add(
                                ImportOcrRepairWorkItem(
                                    packageName = packageName,
                                    year = year,
                                    tableName = tableName,
                                    dbPath = resolvedDbPath,
                                    candidateCount = count,
                                )
                            )
                            candidateRows += count
                        }
                    } catch (e: Exception) {
                        state.appendWarning("扫描分库失败: $packageName/$year err=${e.message}")
                    } finally {
                        try { shardDb?.close() } catch (_: Exception) {}
                    }
                }
            }

            state.works.clear()
            state.works.addAll(works)
            state.totalWorks = works.size
            state.candidateRows = candidateRows
            state.currentWorkIndex = 0
            state.currentLastId = 0
            state.currentPackageName = ""
            state.currentYear = 0
            state.currentTableName = ""
            state.updatedAt = System.currentTimeMillis()

            if (candidateRows <= 0) {
                state.status = ImportOcrRepairTaskState.STATUS_COMPLETED
                state.completedAt = state.updatedAt
                state.appendWarning(
                    if (state.onlyMissing) "未发现缺失 OCR 的图片记录。" else "没有可执行 OCR 修复的图片记录。"
                )
            } else {
                state.status = ImportOcrRepairTaskState.STATUS_PENDING
            }

            ImportOcrRepairTaskStore.save(this, state)
            FileLogger.i(
                STATUS_TAG,
                "OCR 修复任务准备完成: works=${state.totalWorks} candidates=${state.candidateRows}"
            )
            return state
        } finally {
            try { masterDb?.close() } catch (_: Exception) {}
        }
    }

    private fun processPreparedWorks(
        state: ImportOcrRepairTaskState
    ): ImportOcrRepairTaskState {
        val recognizer = TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build()
        )
        try {
            while (state.currentWorkIndex < state.works.size) {
                if (_isCancellationRequested()) {
                    state.status = ImportOcrRepairTaskState.STATUS_CANCELLED
                    return state
                }
                val work = state.works[state.currentWorkIndex]
                state.currentPackageName = work.packageName
                state.currentYear = work.year
                state.currentTableName = work.tableName
                state.updatedAt = System.currentTimeMillis()
                ImportOcrRepairTaskStore.save(this, state)
                updateNotification(state)

                var shardDb: SQLiteDatabase? = null
                try {
                    shardDb = SQLiteDatabase.openDatabase(
                        work.dbPath,
                        null,
                        SQLiteDatabase.OPEN_READWRITE,
                    )
                    ensureOcrColumns(shardDb, work.tableName)

                    while (true) {
                        if (_isCancellationRequested()) {
                            state.status = ImportOcrRepairTaskState.STATUS_CANCELLED
                            return state
                        }
                        val rows = queryBatchRows(
                            db = shardDb,
                            tableName = work.tableName,
                            onlyMissing = state.onlyMissing,
                            lastId = state.currentLastId,
                            batchSize = state.batchSize,
                        )
                        if (rows.isEmpty()) break

                        shardDb.beginTransactionNonExclusive()
                        try {
                            for (row in rows) {
                                if (_isCancellationRequested()) {
                                    state.status = ImportOcrRepairTaskState.STATUS_CANCELLED
                                    break
                                }
                                processRow(
                                    state = state,
                                    db = shardDb,
                                    tableName = work.tableName,
                                    row = row,
                                    recognizer = recognizer,
                                )
                            }
                            shardDb.setTransactionSuccessful()
                        } finally {
                            try { shardDb.endTransaction() } catch (_: Exception) {}
                        }

                        state.updatedAt = System.currentTimeMillis()
                        ImportOcrRepairTaskStore.save(this, state)
                        updateNotification(state)
                    }

                    state.currentWorkIndex += 1
                    state.currentLastId = 0
                    state.updatedAt = System.currentTimeMillis()
                    ImportOcrRepairTaskStore.save(this, state)
                } finally {
                    try { shardDb?.close() } catch (_: Exception) {}
                }
            }

            if (state.status != ImportOcrRepairTaskState.STATUS_CANCELLED) {
                state.status = ImportOcrRepairTaskState.STATUS_COMPLETED
            }
            state.completedAt = System.currentTimeMillis()
            state.updatedAt = state.completedAt
            ImportOcrRepairTaskStore.save(this, state)
            return state
        } catch (e: Exception) {
            state.status = ImportOcrRepairTaskState.STATUS_FAILED
            state.lastError = e.message ?: e.toString()
            state.completedAt = System.currentTimeMillis()
            state.updatedAt = state.completedAt
            state.appendError("执行 OCR 修复失败: ${state.lastError}")
            ImportOcrRepairTaskStore.save(this, state)
            throw e
        } finally {
            try { recognizer.close() } catch (_: Exception) {}
        }
    }

    private fun processRow(
        state: ImportOcrRepairTaskState,
        db: SQLiteDatabase,
        tableName: String,
        row: ImportOcrRepairRow,
        recognizer: TextRecognizer,
    ) {
        val filePath = row.filePath.trim()
        if (filePath.isEmpty()) {
            state.failedRows += 1
            state.processedRows += 1
            state.currentLastId = row.id
            state.appendWarning("空 file_path: ${state.currentPackageName}/${state.currentTableName}#${row.id}")
            return
        }

        val imageFile = File(filePath)
        if (!imageFile.exists()) {
            state.missingFiles += 1
            state.processedRows += 1
            state.currentLastId = row.id
            return
        }

        try {
            val bitmap = android.graphics.BitmapFactory.decodeFile(filePath)
                ?: throw IllegalStateException("decode image failed")
            val recognizedText = try {
                val image = InputImage.fromBitmap(bitmap, 0)
                Tasks.await(recognizer.process(image))?.text?.trim()?.takeIf { it.isNotEmpty() }
            } finally {
                try { bitmap.recycle() } catch (_: Exception) {}
            }

            if (recognizedText != null) {
                val values = ContentValues().apply {
                    put("ocr_text", recognizedText)
                    put("updated_at", System.currentTimeMillis())
                }
                db.update(tableName, values, "id = ?", arrayOf(row.id.toString()))
                state.updatedRows += 1
            } else {
                state.emptyTextRows += 1
            }
        } catch (e: Exception) {
            state.failedRows += 1
            state.appendWarning("OCR 失败: ${filePath} err=${e.message}")
        } finally {
            state.processedRows += 1
            state.currentLastId = row.id
        }
    }

    private fun finishTask(state: ImportOcrRepairTaskState) {
        val text = buildTaskReport(state)
        when (state.status) {
            ImportOcrRepairTaskState.STATUS_COMPLETED -> FileLogger.i(STATUS_TAG, text)
            ImportOcrRepairTaskState.STATUS_CANCELLED -> FileLogger.w(STATUS_TAG, text)
            ImportOcrRepairTaskState.STATUS_FAILED -> FileLogger.e(STATUS_TAG, text)
            else -> FileLogger.i(STATUS_TAG, text)
        }

        try {
            stopForeground(false)
        } catch (_: Exception) {}

        try {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
        } catch (_: Exception) {}

        stopSelf()
    }

    private fun startAsForeground(state: ImportOcrRepairTaskState) {
        val notification = buildNotification(state)
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    private fun updateNotification(state: ImportOcrRepairTaskState) {
        try {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
        } catch (_: Exception) {}
    }

    private fun buildNotification(state: ImportOcrRepairTaskState): Notification {
        val title = when (state.status) {
            ImportOcrRepairTaskState.STATUS_PREPARING -> getString(R.string.import_ocr_notif_preparing_title)
            ImportOcrRepairTaskState.STATUS_COMPLETED -> getString(R.string.import_ocr_notif_done_title)
            ImportOcrRepairTaskState.STATUS_FAILED -> getString(R.string.import_ocr_notif_failed_title)
            ImportOcrRepairTaskState.STATUS_CANCELLED -> getString(R.string.import_ocr_notif_cancelled_title)
            else -> getString(R.string.import_ocr_notif_running_title)
        }

        val detail = when (state.status) {
            ImportOcrRepairTaskState.STATUS_PREPARING ->
                getString(R.string.import_ocr_notif_preparing_text)
            ImportOcrRepairTaskState.STATUS_COMPLETED ->
                getString(
                    R.string.import_ocr_notif_done_text,
                    state.updatedRows,
                    state.emptyTextRows,
                )
            ImportOcrRepairTaskState.STATUS_FAILED ->
                state.lastError ?: getString(R.string.import_ocr_notif_failed_generic)
            ImportOcrRepairTaskState.STATUS_CANCELLED ->
                getString(R.string.import_ocr_notif_cancelled_text)
            else -> {
                val currentScope = if (state.currentPackageName.isNotBlank() &&
                    state.currentTableName.isNotBlank()
                ) {
                    "${state.currentPackageName} · ${state.currentTableName}"
                } else {
                    getString(R.string.import_ocr_notif_running_scope_default)
                }
                val summary = getString(
                    R.string.import_ocr_notif_running_text,
                    state.processedRows,
                    state.candidateRows,
                    state.progressPercentText(),
                )
                "$summary\n$currentScope"
            }
        }

        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(detail.lineSequence().firstOrNull() ?: detail)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        when (state.status) {
            ImportOcrRepairTaskState.STATUS_PREPARING -> {
                builder.setOngoing(true)
                builder.setProgress(0, 0, true)
            }
            ImportOcrRepairTaskState.STATUS_RUNNING,
            ImportOcrRepairTaskState.STATUS_PENDING -> {
                builder.setOngoing(true)
                builder.setProgress(
                    state.candidateRows.coerceAtLeast(1),
                    state.processedRows.coerceAtMost(state.candidateRows.coerceAtLeast(1)),
                    false,
                )
            }
            else -> {
                builder.setOngoing(false)
                builder.setAutoCancel(true)
            }
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.import_ocr_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.import_ocr_channel_desc)
            setShowBadge(false)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "screen_memo:import_ocr_repair"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "申请唤醒锁失败：${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun tableExists(db: SQLiteDatabase, tableName: String): Boolean {
        var cursor: Cursor? = null
        return try {
            cursor = db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
                arrayOf(tableName),
            )
            cursor.moveToFirst()
        } catch (_: Exception) {
            false
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
        }
    }

    private fun countCandidateRows(
        db: SQLiteDatabase,
        tableName: String,
        onlyMissing: Boolean,
    ): Int {
        var cursor: Cursor? = null
        return try {
            cursor = db.rawQuery(
                if (onlyMissing) {
                    "SELECT COUNT(*) FROM $tableName WHERE ocr_text IS NULL OR LENGTH(TRIM(ocr_text)) = 0"
                } else {
                    "SELECT COUNT(*) FROM $tableName"
                },
                emptyArray(),
            )
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        } catch (_: Exception) {
            0
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
        }
    }

    private fun queryBatchRows(
        db: SQLiteDatabase,
        tableName: String,
        onlyMissing: Boolean,
        lastId: Int,
        batchSize: Int,
    ): List<ImportOcrRepairRow> {
        val rows = ArrayList<ImportOcrRepairRow>(batchSize)
        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery(
                if (onlyMissing) {
                    "SELECT id, file_path FROM $tableName WHERE id > ? AND (ocr_text IS NULL OR LENGTH(TRIM(ocr_text)) = 0) ORDER BY id ASC LIMIT ?"
                } else {
                    "SELECT id, file_path FROM $tableName WHERE id > ? ORDER BY id ASC LIMIT ?"
                },
                arrayOf(lastId.toString(), batchSize.toString()),
            )
            while (cursor.moveToNext()) {
                rows.add(
                    ImportOcrRepairRow(
                        id = cursor.getIntOrNull(0) ?: continue,
                        filePath = cursor.getStringOrNull(1).orEmpty(),
                    )
                )
            }
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
        }
        return rows
    }

    private fun ensureOcrColumns(db: SQLiteDatabase, tableName: String) {
        try { db.execSQL("ALTER TABLE $tableName ADD COLUMN ocr_text TEXT") } catch (_: Exception) {}
        try { db.execSQL("ALTER TABLE $tableName ADD COLUMN updated_at INTEGER") } catch (_: Exception) {}
    }

    private fun monthTableName(year: Int, month: Int): String {
        val mm = if (month < 10) "0$month" else month.toString()
        return "shots_${year}${mm}"
    }

    private fun buildTaskReport(state: ImportOcrRepairTaskState): String {
        val sb = StringBuilder()
        sb.appendLine("ScreenMemo 导入图片文字修复")
        sb.appendLine("状态: ${state.status}")
        sb.appendLine("开始: ${state.startedAt}")
        sb.appendLine("结束: ${state.completedAt}")
        sb.appendLine("候选: ${state.candidateRows}")
        sb.appendLine("已处理: ${state.processedRows}")
        sb.appendLine("写入 OCR: ${state.updatedRows}")
        sb.appendLine("空文本: ${state.emptyTextRows}")
        sb.appendLine("失败: ${state.failedRows}")
        sb.appendLine("缺文件: ${state.missingFiles}")
        if (state.lastError != null) {
            sb.appendLine("lastError: ${state.lastError}")
        }
        if (state.warnings.isNotEmpty()) {
            sb.appendLine("[警告]")
            state.warnings.forEach { sb.appendLine("- $it") }
        }
        if (state.errors.isNotEmpty()) {
            sb.appendLine("[错误]")
            state.errors.forEach { sb.appendLine("- $it") }
        }
        return sb.toString().trim()
    }

    private fun _isCancellationRequested(): Boolean {
        return ImportOcrRepairTaskStore.load(this)?.status ==
            ImportOcrRepairTaskState.STATUS_CANCELLED
    }
}

private data class ImportOcrRepairRow(
    val id: Int,
    val filePath: String,
)

private data class ImportOcrRepairWorkItem(
    val packageName: String,
    val year: Int,
    val tableName: String,
    val dbPath: String,
    val candidateCount: Int,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("packageName", packageName)
            .put("year", year)
            .put("tableName", tableName)
            .put("dbPath", dbPath)
            .put("candidateCount", candidateCount)
    }

    companion object {
        fun fromJson(obj: JSONObject): ImportOcrRepairWorkItem {
            return ImportOcrRepairWorkItem(
                packageName = obj.optString("packageName", ""),
                year = obj.optInt("year", 0),
                tableName = obj.optString("tableName", ""),
                dbPath = obj.optString("dbPath", ""),
                candidateCount = obj.optInt("candidateCount", 0),
            )
        }
    }
}

private data class ImportOcrRepairTaskState(
    val taskId: String,
    var status: String,
    val onlyMissing: Boolean,
    val batchSize: Int,
    val startedAt: Long,
    var updatedAt: Long,
    var completedAt: Long,
    var candidateRows: Int,
    var processedRows: Int,
    var updatedRows: Int,
    var emptyTextRows: Int,
    var failedRows: Int,
    var missingFiles: Int,
    var currentWorkIndex: Int,
    var currentLastId: Int,
    var currentPackageName: String,
    var currentYear: Int,
    var currentTableName: String,
    var totalWorks: Int,
    var lastError: String?,
    val warnings: MutableList<String>,
    val errors: MutableList<String>,
    val works: MutableList<ImportOcrRepairWorkItem>,
) {
    companion object {
        const val STATUS_IDLE = "idle"
        const val STATUS_PREPARING = "preparing"
        const val STATUS_PENDING = "pending"
        const val STATUS_RUNNING = "running"
        const val STATUS_COMPLETED = "completed"
        const val STATUS_FAILED = "failed"
        const val STATUS_CANCELLED = "cancelled"

        fun idle(): ImportOcrRepairTaskState {
            return ImportOcrRepairTaskState(
                taskId = "",
                status = STATUS_IDLE,
                onlyMissing = true,
                batchSize = 12,
                startedAt = 0L,
                updatedAt = 0L,
                completedAt = 0L,
                candidateRows = 0,
                processedRows = 0,
                updatedRows = 0,
                emptyTextRows = 0,
                failedRows = 0,
                missingFiles = 0,
                currentWorkIndex = 0,
                currentLastId = 0,
                currentPackageName = "",
                currentYear = 0,
                currentTableName = "",
                totalWorks = 0,
                lastError = null,
                warnings = mutableListOf(),
                errors = mutableListOf(),
                works = mutableListOf(),
            )
        }
    }

    fun isRecoverable(): Boolean {
        return status == STATUS_PREPARING || status == STATUS_PENDING || status == STATUS_RUNNING
    }

    fun hasPreparedWorks(): Boolean = works.isNotEmpty() || totalWorks > 0

    fun progressPercentText(): String {
        if (candidateRows <= 0) return "0%"
        val ratio = processedRows.toDouble() / candidateRows.toDouble()
        return String.format("%.1f%%", (ratio * 100.0).coerceIn(0.0, 100.0))
    }

    fun appendWarning(message: String) {
        if (message.isBlank()) return
        if (warnings.size >= 20) return
        warnings.add(message)
    }

    fun appendError(message: String) {
        if (message.isBlank()) return
        if (errors.size >= 20) return
        errors.add(message)
    }

    fun toMap(): Map<String, Any?> {
        return hashMapOf(
            "taskId" to taskId,
            "status" to status,
            "onlyMissing" to onlyMissing,
            "batchSize" to batchSize,
            "startedAt" to startedAt,
            "updatedAt" to updatedAt,
            "completedAt" to completedAt,
            "candidateRows" to candidateRows,
            "processedRows" to processedRows,
            "updatedRows" to updatedRows,
            "emptyTextRows" to emptyTextRows,
            "failedRows" to failedRows,
            "missingFiles" to missingFiles,
            "currentWorkIndex" to currentWorkIndex,
            "currentLastId" to currentLastId,
            "currentPackageName" to currentPackageName,
            "currentYear" to currentYear,
            "currentTableName" to currentTableName,
            "totalWorks" to totalWorks,
            "lastError" to lastError,
            "warnings" to ArrayList(warnings),
            "errors" to ArrayList(errors),
            "isActive" to isRecoverable(),
            "progressPercent" to progressPercentText(),
        )
    }
}

private object ImportOcrRepairTaskStore {
    private const val PREFS_NAME = "import_ocr_repair_task_state"
    private const val KEY_TASK_JSON = "task_json"

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    @Synchronized
    fun load(context: Context): ImportOcrRepairTaskState? {
        val raw = prefs(context).getString(KEY_TASK_JSON, null)?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return try {
            val obj = JSONObject(raw)
            val warnings = mutableListOf<String>()
            val errors = mutableListOf<String>()
            val works = mutableListOf<ImportOcrRepairWorkItem>()
            val warningsJson = obj.optJSONArray("warnings") ?: JSONArray()
            for (i in 0 until warningsJson.length()) {
                warnings.add(warningsJson.optString(i))
            }
            val errorsJson = obj.optJSONArray("errors") ?: JSONArray()
            for (i in 0 until errorsJson.length()) {
                errors.add(errorsJson.optString(i))
            }
            val worksJson = obj.optJSONArray("works") ?: JSONArray()
            for (i in 0 until worksJson.length()) {
                val item = worksJson.optJSONObject(i) ?: continue
                works.add(ImportOcrRepairWorkItem.fromJson(item))
            }
            ImportOcrRepairTaskState(
                taskId = obj.optString("taskId", ""),
                status = obj.optString("status", ImportOcrRepairTaskState.STATUS_IDLE),
                onlyMissing = obj.optBoolean("onlyMissing", true),
                batchSize = obj.optInt("batchSize", 12),
                startedAt = obj.optLong("startedAt", 0L),
                updatedAt = obj.optLong("updatedAt", 0L),
                completedAt = obj.optLong("completedAt", 0L),
                candidateRows = obj.optInt("candidateRows", 0),
                processedRows = obj.optInt("processedRows", 0),
                updatedRows = obj.optInt("updatedRows", 0),
                emptyTextRows = obj.optInt("emptyTextRows", 0),
                failedRows = obj.optInt("failedRows", 0),
                missingFiles = obj.optInt("missingFiles", 0),
                currentWorkIndex = obj.optInt("currentWorkIndex", 0),
                currentLastId = obj.optInt("currentLastId", 0),
                currentPackageName = obj.optString("currentPackageName", ""),
                currentYear = obj.optInt("currentYear", 0),
                currentTableName = obj.optString("currentTableName", ""),
                totalWorks = obj.optInt("totalWorks", works.size),
                lastError = obj.optString("lastError", "").takeIf { it.isNotBlank() },
                warnings = warnings,
                errors = errors,
                works = works,
            )
        } catch (e: Exception) {
            FileLogger.e("ImportOcrRepairTaskStore", "读取 OCR 修复状态失败", e)
            null
        }
    }

    @Synchronized
    fun save(context: Context, state: ImportOcrRepairTaskState) {
        val warnings = JSONArray()
        state.warnings.forEach { warnings.put(it) }
        val errors = JSONArray()
        state.errors.forEach { errors.put(it) }
        val works = JSONArray()
        state.works.forEach { works.put(it.toJson()) }
        val obj = JSONObject()
            .put("taskId", state.taskId)
            .put("status", state.status)
            .put("onlyMissing", state.onlyMissing)
            .put("batchSize", state.batchSize)
            .put("startedAt", state.startedAt)
            .put("updatedAt", state.updatedAt)
            .put("completedAt", state.completedAt)
            .put("candidateRows", state.candidateRows)
            .put("processedRows", state.processedRows)
            .put("updatedRows", state.updatedRows)
            .put("emptyTextRows", state.emptyTextRows)
            .put("failedRows", state.failedRows)
            .put("missingFiles", state.missingFiles)
            .put("currentWorkIndex", state.currentWorkIndex)
            .put("currentLastId", state.currentLastId)
            .put("currentPackageName", state.currentPackageName)
            .put("currentYear", state.currentYear)
            .put("currentTableName", state.currentTableName)
            .put("totalWorks", state.totalWorks)
            .put("lastError", state.lastError ?: JSONObject.NULL)
            .put("warnings", warnings)
            .put("errors", errors)
            .put("works", works)

        prefs(context).edit().putString(KEY_TASK_JSON, obj.toString()).commit()
    }
}

private fun Cursor.getStringOrNull(index: Int): String? {
    return if (isNull(index)) null else getString(index)
}

private fun Cursor.getIntOrNull(index: Int): Int? {
    return if (isNull(index)) null else getInt(index)
}
