package com.fqyw.screen_memo.storage

import android.app.AppOpsManager
import android.app.usage.StorageStats
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.os.UserHandle
import android.os.storage.StorageManager
import androidx.annotation.RequiresApi
import com.fqyw.screen_memo.FileLogger
import java.io.File

/**
 * 负责生成应用内部存储占用的详细分析数据。
 *
 * - 优先通过 StorageStatsManager 获取与系统设置一致的占用数值（需 UsageStats 权限）。
 * - 同时对应用私有目录进行逐级扫描，输出截图、数据库等细项的大小。
 * - 结果通过 MethodChannel 传递给 Flutter 侧进行展示。
 */
object StorageAnalyzer {

    private const val TAG = "StorageAnalyzer"
    private const val SCREEN_NODE_LIMIT = 30

    private data class SizeInfo(
        val bytes: Long,
        val fileCount: Long,
    )

    private data class StorageNode(
        val id: String,
        val label: String,
        val bytes: Long,
        val fileCount: Long,
        val path: String? = null,
        val type: String = "directory",
        val extra: Map<String, Any?> = emptyMap(),
        val children: List<StorageNode> = emptyList(),
    ) {
        fun toMap(): Map<String, Any?> {
            val map = mutableMapOf<String, Any?>(
                "id" to id,
                "label" to label,
                "bytes" to bytes,
                "fileCount" to fileCount,
                "type" to type,
            )
            path?.let { map["path"] = it }
            if (extra.isNotEmpty()) {
                map["extra"] = extra
            }
            if (children.isNotEmpty()) {
                map["children"] = children.map { it.toMap() }
            }
            return map
        }
    }

    fun collect(context: Context): Map<String, Any?> {
        val startTs = System.currentTimeMillis()
        val hasUsagePermission = hasUsageStatsPermission(context)
        val statsResult = loadStorageStats(context, hasUsagePermission)

        val packageManager = context.packageManager

        val filesNode = analyzeFilesDir(context.filesDir, packageManager)
        val sharedPrefsNode = analyzeDir(
            dir = safeChild(context, "shared_prefs"),
            id = "shared_prefs",
            label = "shared_prefs",
            type = "sharedPrefs",
        )
        val noBackupNode = analyzeDir(
            dir = context.noBackupFilesDir,
            id = "no_backup",
            label = "no_backup",
            type = "noBackup",
        )
        val appFlutterNode = analyzeDir(
            dir = safeChild(context, "app_flutter"),
            id = "app_flutter",
            label = "app_flutter",
            type = "appFlutter",
        )
        val databasesDir = analyzeDir(
            dir = safeChild(context, "databases"),
            id = "databases",
            label = "databases",
            type = "databases",
        )

        val dataChildren = listOfNotNull(
            filesNode,
            databasesDir,
            sharedPrefsNode,
            noBackupNode,
            appFlutterNode,
        )
        val dataNode = StorageNode(
            id = "data",
            label = "App Data",
            bytes = dataChildren.sumOf { it.bytes },
            fileCount = dataChildren.sumOf { it.fileCount },
            type = "group",
            children = sortNodes(dataChildren),
        )

        val cacheDirNode = analyzeDir(
            dir = context.cacheDir,
            id = "cache_dir",
            label = "cache",
            type = "cacheDir",
        )
        val codeCacheNode = analyzeDir(
            dir = context.codeCacheDir,
            id = "code_cache",
            label = "code_cache",
            type = "codeCache",
        )
        val cacheChildren = listOfNotNull(cacheDirNode, codeCacheNode)
        val cacheNode = StorageNode(
            id = "cache",
            label = "Cache",
            bytes = cacheChildren.sumOf { it.bytes },
            fileCount = cacheChildren.sumOf { it.fileCount },
            type = "group",
            children = sortNodes(cacheChildren),
        )

        val externalLogsNode = analyzeExternalLogs(context)

        val nodes = mutableListOf<StorageNode>()
        statsResult.storageStats?.let {
            nodes += StorageNode(
                id = "app",
                label = "Application Binary",
                bytes = it.appBytes,
                fileCount = 0,
                type = "appBinary",
            )
        }
        nodes += dataNode
        nodes += cacheNode
        externalLogsNode?.let { nodes += it }

        val manualTotalBytes =
            dataNode.bytes + cacheNode.bytes + (externalLogsNode?.bytes ?: 0L) +
                (statsResult.storageStats?.appBytes ?: 0L)

        val duration = System.currentTimeMillis() - startTs

        val result = mutableMapOf<String, Any?>(
            "timestamp" to System.currentTimeMillis(),
            "scanDurationMs" to duration,
            "hasUsageStatsPermission" to hasUsagePermission,
            "statsAvailable" to (statsResult.storageStats != null),
            "nodes" to nodes.map { it.toMap() },
            "manualTotalBytes" to manualTotalBytes,
            "manualDataBytes" to dataNode.bytes,
            "manualCacheBytes" to cacheNode.bytes,
            "manualExternalBytes" to (externalLogsNode?.bytes ?: 0L),
            "errors" to statsResult.errors,
        )

        statsResult.storageStats?.let { storageStats ->
            result["totalBytes"] = storageStats.appBytes + storageStats.dataBytes + storageStats.cacheBytes
            result["appBytes"] = storageStats.appBytes
            result["dataBytes"] = storageStats.dataBytes
            result["cacheBytes"] = storageStats.cacheBytes
        }

        statsResult.storageUuid?.let { result["storageUuid"] = it }
        statsResult.externalBytes?.let { result["externalBytes"] = it }

        return result
    }

    private fun analyzeFilesDir(dir: File?, packageManager: PackageManager): StorageNode? {
        if (dir == null || !dir.exists()) return null
        val childrenNodes = mutableListOf<StorageNode>()
        val entries = safeListFiles(dir)
        var totalBytes = 0L
        var totalFiles = 0L
        entries.forEach { child ->
            val node = when {
                child.isDirectory && child.name == "output" -> analyzeOutputDir(child, packageManager)
                child.isDirectory -> analyzeDir(
                    dir = child,
                    id = "files::${child.name}",
                    label = child.name,
                    type = "filesChild",
                )
                child.isFile -> {
                    val info = SizeInfo(bytes = safeLength(child), fileCount = 1)
                    StorageNode(
                        id = "files::file::${child.name}",
                        label = child.name,
                        bytes = info.bytes,
                        fileCount = info.fileCount,
                        path = child.absolutePath,
                        type = "file",
                    )
                }
                else -> null
            }
            if (node != null) {
                totalBytes += node.bytes
                totalFiles += node.fileCount
                childrenNodes += node
            }
        }

        return StorageNode(
            id = "files",
            label = "files",
            bytes = totalBytes,
            fileCount = totalFiles,
            path = dir.absolutePath,
            type = "filesRoot",
            children = sortNodes(childrenNodes),
        )
    }

    private fun analyzeOutputDir(dir: File, packageManager: PackageManager): StorageNode {
        val childrenNodes = mutableListOf<StorageNode>()
        val entries = safeListFiles(dir)
        var totalBytes = 0L
        var totalFiles = 0L

        entries.forEach { child ->
            val node = when {
                child.isDirectory && child.name == "screen" -> analyzeScreenshotsDir(child, packageManager)
                child.isDirectory && child.name == "databases" -> analyzeDir(
                    dir = child,
                    id = "output::databases",
                    label = "databases",
                    type = "outputDatabases",
                )
                child.isDirectory -> analyzeDir(
                    dir = child,
                    id = "output::${child.name}",
                    label = child.name,
                    type = "outputChild",
                )
                child.isFile -> StorageNode(
                    id = "output::file::${child.name}",
                    label = child.name,
                    bytes = safeLength(child),
                    fileCount = 1,
                    path = child.absolutePath,
                    type = "file",
                )
                else -> null
            }
            if (node != null) {
                totalBytes += node.bytes
                totalFiles += node.fileCount
                childrenNodes += node
            }
        }

        return StorageNode(
            id = "output",
            label = "output",
            bytes = totalBytes,
            fileCount = totalFiles,
            path = dir.absolutePath,
            type = "outputRoot",
            children = sortNodes(childrenNodes),
        )
    }

    private fun analyzeScreenshotsDir(dir: File, packageManager: PackageManager): StorageNode {
        val entries = safeListFiles(dir)
        val packageNodes = mutableListOf<StorageNode>()

        var totalBytes = 0L
        var totalFiles = 0L

        entries.forEach { child ->
            val node = if (child.isDirectory) {
                val info = measureDirectory(child)
                totalBytes += info.bytes
                totalFiles += info.fileCount
                StorageNode(
                    id = "screenshots::${child.name}",
                    label = resolveAppLabel(packageManager, child.name),
                    bytes = info.bytes,
                    fileCount = info.fileCount,
                    path = child.absolutePath,
                    type = "screenshotsPackage",
                    extra = mapOf(
                        "packageName" to child.name,
                        "appName" to resolveAppLabel(packageManager, child.name),
                    ),
                )
            } else if (child.isFile) {
                val size = safeLength(child)
                totalBytes += size
                totalFiles += 1
                StorageNode(
                    id = "screenshots::file::${child.name}",
                    label = child.name,
                    bytes = size,
                    fileCount = 1,
                    path = child.absolutePath,
                    type = "file",
                )
            } else {
                null
            }

            node?.let { packageNodes += it }
        }

        val sorted = packageNodes.sortedByDescending { it.bytes }
        val limited = limitNodes(sorted, SCREEN_NODE_LIMIT, prefix = "screenshots::others")

        return StorageNode(
            id = "screenshots",
            label = "screenshots",
            bytes = totalBytes,
            fileCount = totalFiles,
            path = dir.absolutePath,
            type = "screenshotsRoot",
            children = limited,
        )
    }

    private fun analyzeExternalLogs(context: Context): StorageNode? {
        val dir = context.getExternalFilesDir("output/logs") ?: return null
        if (!dir.exists()) return null
        val info = measureDirectory(dir)
        return StorageNode(
            id = "external_logs",
            label = "external_logs",
            bytes = info.bytes,
            fileCount = info.fileCount,
            path = dir.absolutePath,
            type = "externalLogs",
        )
    }

    private fun analyzeDir(
        dir: File?,
        id: String,
        label: String,
        type: String,
    ): StorageNode? {
        if (dir == null || !dir.exists()) return null
        if (dir.isFile) {
            val size = safeLength(dir)
            return StorageNode(
                id = id,
                label = label,
                bytes = size,
                fileCount = 1,
                path = dir.absolutePath,
                type = "file",
            )
        }
        val info = measureDirectory(dir)
        if (info.bytes == 0L && info.fileCount == 0L) return null
        return StorageNode(
            id = id,
            label = label,
            bytes = info.bytes,
            fileCount = info.fileCount,
            path = dir.absolutePath,
            type = type,
        )
    }

    private fun sortNodes(nodes: List<StorageNode>): List<StorageNode> =
        nodes.sortedWith(compareByDescending<StorageNode> { it.bytes }.thenBy { it.label })

    private fun limitNodes(
        nodes: List<StorageNode>,
        limit: Int,
        prefix: String,
    ): List<StorageNode> {
        if (nodes.size <= limit) return nodes
        if (limit < 2) return nodes
        val keep = nodes.take(limit - 1)
        val rest = nodes.drop(limit - 1)
        val restBytes = rest.sumOf { it.bytes }
        val restFiles = rest.sumOf { it.fileCount }
        if (restBytes <= 0L && restFiles <= 0L) return keep
        val othersNode = StorageNode(
            id = prefix,
            label = "others",
            bytes = restBytes,
            fileCount = restFiles,
            type = "aggregated",
            extra = mapOf("count" to rest.size),
        )
        return keep + othersNode
    }

    private fun resolveAppLabel(packageManager: PackageManager, packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo)?.toString() ?: packageName
        } catch (e: Exception) {
            packageName
        }
    }

    private data class StorageStatsResult(
        val storageStats: StorageStats?,
        val externalBytes: Long?,
        val storageUuid: String?,
        val errors: List<String>,
    )

    private fun loadStorageStats(
        context: Context,
        hasUsagePermission: Boolean,
    ): StorageStatsResult {
        if (!hasUsagePermission || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return StorageStatsResult(null, null, null, emptyList())
        }
        val errors = mutableListOf<String>()
        val storageManager = context.getSystemService(StorageManager::class.java)
        val statsManager = context.getSystemService(StorageStatsManager::class.java)
        if (storageManager == null || statsManager == null) {
            errors += "service_unavailable"
            return StorageStatsResult(null, null, null, errors)
        }
        val uuid = StorageManager.UUID_DEFAULT
        val userHandle: UserHandle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            UserHandle.getUserHandleForUid(Process.myUid())
        } else {
            Process.myUserHandle()
        }

        var storageStats: StorageStats? = null
        var externalBytes: Long? = null

        try {
            storageStats = statsManager.queryStatsForPackage(uuid, context.packageName, userHandle)
        } catch (e: Exception) {
            errors += "internal_stats_error:${e.message}"
            FileLogger.w(TAG, "queryStatsForPackage failed: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 部分平台 SDK 未暴露 queryExternalStatsForPackage，反射调用以保持兼容
            try {
                val method = StorageStatsManager::class.java.getMethod(
                    "queryExternalStatsForPackage",
                    java.util.UUID::class.java,
                    String::class.java,
                    UserHandle::class.java,
                )
                val stats = method.invoke(statsManager, uuid, context.packageName, userHandle)
                val totalBytesMethod = stats?.javaClass?.getMethod("getTotalBytes")
                externalBytes = (totalBytesMethod?.invoke(stats) as? Long)
            } catch (e: ReflectiveOperationException) {
                FileLogger.i(TAG, "queryExternalStatsForPackage not available on this device: ${e.message}")
            } catch (e: SecurityException) {
                FileLogger.i(TAG, "queryExternalStatsForPackage blocked by security policy: ${e.message}")
            } catch (e: Exception) {
                errors += "external_stats_error:${e.message}"
                FileLogger.w(TAG, "queryExternalStatsForPackage invocation failed: ${e.message}")
            }
        }

        return StorageStatsResult(
            storageStats = storageStats,
            externalBytes = externalBytes,
            storageUuid = uuid.toString(),
            errors = errors,
        )
    }

    private fun hasUsageStatsPermission(context: Context): Boolean {
        return try {
            val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            FileLogger.w(TAG, "check usage stats permission failed: ${e.message}")
            false
        }
    }

    private fun measureDirectory(dir: File): SizeInfo {
        if (!dir.exists()) return SizeInfo(0L, 0L)
        if (dir.isFile) {
            val size = safeLength(dir)
            return SizeInfo(size, 1L)
        }
        var totalBytes = 0L
        var totalFiles = 0L
        val stack = ArrayDeque<File>()
        stack.add(dir)
        while (stack.isNotEmpty()) {
            val current = stack.removeFirst()
            val list = safeListFiles(current)
            list.forEach { file ->
                if (file.isFile) {
                    totalBytes += safeLength(file)
                    totalFiles += 1
                } else if (file.isDirectory) {
                    stack.add(file)
                }
            }
        }
        return SizeInfo(totalBytes, totalFiles)
    }

    private fun safeListFiles(dir: File): List<File> {
        return try {
            dir.listFiles()?.toList() ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun safeLength(file: File): Long {
        return try {
            file.length()
        } catch (_: Exception) {
            0L
        }
    }

    private fun safeChild(context: Context, name: String): File? {
        val base = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.dataDir
        } else {
            File(context.applicationInfo.dataDir)
        }
        val target = File(base, name)
        return if (target.exists()) target else null
    }
}


