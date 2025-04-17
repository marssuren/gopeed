package com.gopeed.gopeed

import androidx.annotation.NonNull
import com.gopeed.libgopeed.Libgopeed
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    private val CHANNEL = "gopeed.com/libgopeed"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val taskQueue =
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
            StandardMethodCodec.INSTANCE,
            taskQueue
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // --- 现有的 Gopeed 方法 ---
                "start" -> {
                    val cfg = call.argument<String>("cfg")
                    try {
                         // 调用 Go 生成的绑定代码
                        val port = Libgopeed.start(cfg)
                        result.success(port)
                    } catch (e: Exception) {
                        // 返回具体的错误代码和消息
                        result.error("ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    // 调用 Go 生成的绑定代码
                    Libgopeed.stop()
                    // 成功，无返回值
                    result.success(null)
                }
                // --- 新增的 IPFS 方法 ---
                "initIPFS" -> {
                    val repoPath = call.argument<String>("repoPath")
                    if (repoPath != null) {
                        try {
                            // 调用 Go 函数 (返回 bool)
                            val success = Libgopeed.initIPFS(repoPath)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("IPFS_INIT_ERROR", e.localizedMessage ?: "初始化 IPFS 仓库失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "initIPFS 缺少 repoPath 参数", null)
                    }
                }
                "startIPFS" -> {
                    val repoPath = call.argument<String>("repoPath")
                    if (repoPath != null) {
                        try {
                            // 调用 Go 函数 (返回 string)
                            val peerId = Libgopeed.startIPFS(repoPath)
                            result.success(peerId)
                        } catch (e: Exception) {
                            result.error("IPFS_START_ERROR", e.localizedMessage ?: "启动 IPFS 节点失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "startIPFS 缺少 repoPath 参数", null)
                    }
                }
                "stopIPFS" -> {
                    try {
                        // 调用 Go 函数 (只返回 error)
                        Libgopeed.stopIPFS()
                        // 成功，无数据返回
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("IPFS_STOP_ERROR", e.localizedMessage ?: "停止 IPFS 节点失败", null)
                    }
                }
                "addFileToIPFS" -> {
                    val content = call.argument<String>("content")
                    if (content != null) {
                        try {
                            // 调用 Go 函数 (返回 string)
                            val cid = Libgopeed.addFileToIPFS(content)
                            result.success(cid)
                        } catch (e: Exception) {
                            result.error("IPFS_ADD_ERROR", e.localizedMessage ?: "添加文件到 IPFS 失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "addFileToIPFS 缺少 content 参数", null)
                    }
                }
                "getFileFromIPFS" -> {
                    val cid = call.argument<String>("cid")
                    if (cid != null) {
                        try {
                            // 调用 Go 函数 (返回 string)
                            val fileContent = Libgopeed.getFileFromIPFS(cid)
                            result.success(fileContent)
                        } catch (e: Exception) {
                            result.error("IPFS_GET_ERROR", e.localizedMessage ?: "从 IPFS 获取文件失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "getFileFromIPFS 缺少 cid 参数", null)
                    }
                }
                "getIPFSPeerID" -> {
                    try {
                        // 这个特定的 Go 函数不返回错误，但 gomobile 可能会包装 panic
                        // 调用 Go 函数 (返回 string)
                        val peerId = Libgopeed.getIPFSPeerID()
                        result.success(peerId)
                    } catch (e: Exception) {
                        result.error("IPFS_PEERID_ERROR", e.localizedMessage ?: "获取 IPFS Peer ID 失败", null)
                    }
                }

                "listDirectoryFromIPFS" -> {
                    val cid = call.argument<String>("cid")
                    if (cid != null) {
                        try {
                            // 调用 Go 函数，它返回 List<Libgopeed.DirectoryEntry>
                            val entries: List<Libgopeed.DirectoryEntry> = Libgopeed.listDirectoryFromIPFS(cid)
                            // 将 Go 返回的结构体列表转换为 Dart 可理解的 Map 列表
                            val resultList = entries.map { entry ->
                                mapOf(
                                    "name" to entry.name,
                                    "cid" to entry.cid,
                                    "type" to entry.type,
                                    "size" to entry.size // Kotlin Long 对应 Dart int
                                )
                            }
                            result.success(resultList)
                        } catch (e: Exception) {
                            result.error("IPFS_LIST_ERROR", e.localizedMessage ?: "列出目录失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "listDirectoryFromIPFS 缺少 cid 参数", null)
                    }
                }

                "startDownloadSelected" -> {
                    val topCid = call.argument<String>("topCid")
                    val localBasePath = call.argument<String>("localBasePath")
                    // 注意：接收 List<String> 参数
                    val selectedPaths = call.argument<List<String>>("selectedPaths")

                    if (topCid != null && localBasePath != null && selectedPaths != null) {
                        try {
                            // 调用 Go 函数
                            val taskId = Libgopeed.startDownloadSelected(topCid, localBasePath, selectedPaths)
                            result.success(taskId) // 返回任务 ID
                        } catch (e: Exception) {
                            result.error("IPFS_DOWNLOAD_START_ERROR", e.localizedMessage ?: "启动下载任务失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "startDownloadSelected 缺少参数 (topCid, localBasePath, or selectedPaths)", null)
                    }
                }

                "queryDownloadProgress" -> {
                    val downloadID = call.argument<String>("downloadID")
                    if (downloadID != null) {
                        try {
                            // 调用 Go 函数，返回 Libgopeed.ProgressInfo
                            val progress: Libgopeed.ProgressInfo = Libgopeed.queryDownloadProgress(downloadID)
                            // 将 Go 结构体转换为 Dart 可理解的 Map
                            val resultMap = mapOf(
                                "totalBytes" to progress.totalBytes,
                                "bytesRetrieved" to progress.bytesRetrieved,
                                "speedBps" to progress.speedBps,
                                "elapsedTimeSec" to progress.elapsedTimeSec,
                                "isCompleted" to progress.isCompleted,
                                "hasError" to progress.hasError,
                                "errorMessage" to progress.errorMessage
                            )
                            result.success(resultMap)
                        } catch (e: Exception) {
                            // 查询失败可能是 ID 不存在，或者 Go 端内部错误
                            result.error("IPFS_QUERY_PROGRESS_ERROR", e.localizedMessage ?: "查询进度失败", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "queryDownloadProgress 缺少 downloadID 参数", null)
                    }
                }

                // --- 默认情况 ---
                else -> {
                    // 如果方法名未匹配，则返回未实现
                    result.notImplemented()
                }
            }
        }
    }

}
