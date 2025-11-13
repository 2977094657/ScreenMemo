package com.fqyw.screen_memo.memory.service

import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.fqyw.screen_memo.FileLogger
import kotlinx.coroutines.launch

class MemoryBackendService : LifecycleService() {

    private val binder = MemoryBinder()
    private lateinit var memoryEngine: MemoryEngine

    override fun onCreate() {
        super.onCreate()
        memoryEngine = MemoryEngine.getInstance(this)
        FileLogger.i(TAG, "MemoryBackendService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val targetEndExclusiveMillis = intent
            ?.getLongExtra(EXTRA_TARGET_END_EXCLUSIVE, -1L)
            ?.takeIf { it > 0L }
        when (intent?.action) {
            ACTION_INIT_HISTORICAL -> {
                lifecycleScope.launch {
                    memoryEngine.initializeHistoricalProcessing(
                        forceReprocess = false,
                        targetEndExclusiveMillis = targetEndExclusiveMillis
                    )
                }
            }
            ACTION_REPROCESS_ALL -> {
                lifecycleScope.launch {
                    memoryEngine.initializeHistoricalProcessing(
                        forceReprocess = true,
                        targetEndExclusiveMillis = targetEndExclusiveMillis
                    )
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder {
        super.onBind(intent)
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()
        FileLogger.i(TAG, "MemoryBackendService destroyed")
    }

    inner class MemoryBinder : Binder() {
        fun getEngine(): MemoryEngine = memoryEngine
    }

    companion object {
        private const val TAG = "MemoryBackendService"
        const val ACTION_INIT_HISTORICAL = "com.fqyw.screen_memo.memory.action.INIT_HISTORICAL"
        const val ACTION_REPROCESS_ALL = "com.fqyw.screen_memo.memory.action.REPROCESS_ALL"
        private const val EXTRA_TARGET_END_EXCLUSIVE =
            "com.fqyw.screen_memo.memory.extra.TARGET_END_EXCLUSIVE"

        fun start(context: Context) {
            val intent = Intent(context, MemoryBackendService::class.java)
            context.startService(intent)
        }

        fun startHistoricalProcessing(
            context: Context,
            forceReprocess: Boolean,
            targetEndExclusiveMillis: Long? = null
        ) {
            val intent = Intent(context, MemoryBackendService::class.java).apply {
                action = if (forceReprocess) ACTION_REPROCESS_ALL else ACTION_INIT_HISTORICAL
                targetEndExclusiveMillis?.let { putExtra(EXTRA_TARGET_END_EXCLUSIVE, it) }
            }
            context.startService(intent)
        }
    }
}

