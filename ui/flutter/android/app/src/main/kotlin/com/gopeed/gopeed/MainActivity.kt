package com.gopeed.gopeed

import androidx.annotation.NonNull
import com.gopeed.libgopeed.Libgopeed
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.json.JSONArray
import org.json.JSONObject
import java.lang.Exception
import android.util.Log

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
                        // 调用现在应该存在的 Go 函数
                        val peerId = Libgopeed.getIPFSPeerID()
                        result.success(peerId)
                    } catch (e: Exception) {
                        result.error("IPFS_PEERID_ERROR", e.localizedMessage ?: "获取 IPFS Peer ID 失败", null)
                    }
                }

                "listDirectoryFromIPFS" -> {
                    val cid = call.argument<String>("cid")
                    Log.d("GoPeedDebug", "Received listDirectoryFromIPFS call for CID: $cid")
                    if (cid != null) {
                        try {
                            // 1. 调用 Go 函数，获取 JSON 字符串
                            val jsonString = Libgopeed.listDirectoryFromIPFS(cid)
                            Log.d("GoPeedDebug", "Got JSON string from Go: $jsonString")

                            // 2. 直接将从 Go 获取的 JSON 字符串发送回 Dart
                            result.success(jsonString) // <--- 关键：发送原始 JSON 字符串

                            // 注意：不再需要在 Kotlin 端解析 JSON 了，解析工作交给 Dart

                        } catch (e: Exception) {
                             Log.e("GoPeedDebug", "Error in listDirectoryFromIPFS: ${e.localizedMessage}", e)
                            result.error("IPFS_LIST_ERROR", e.localizedMessage ?: "列出目录失败", e.toString())
                        }
                    } else {
                        result.error("INVALID_ARGS", "listDirectoryFromIPFS 缺少 cid 参数", null)
                    }
                }

                "startDownloadSelected" -> {
                    val topCid = call.argument<String>("topCid")
                    val localBasePath = call.argument<String>("localBasePath")
                    val selectedPaths = call.argument<List<String>>("selectedPaths")

                    if (topCid != null && localBasePath != null && selectedPaths != null) {
                        try {
                            // --- 将 List<String> 序列化为 JSON 字符串 ---
                            val jsonArray = JSONArray(selectedPaths)
                            val selectedPathsJson = jsonArray.toString()
                            // --- ---

                            // 调用 Go 函数，传递 JSON 字符串
                            val taskId = Libgopeed.startDownloadSelected(topCid, localBasePath, selectedPathsJson)
                            result.success(taskId) // 返回任务 ID
                        } catch (e: Exception) {
                            result.error("IPFS_DOWNLOAD_START_ERROR", e.localizedMessage ?: "启动下载任务失败", e.toString()) // 添加详细错误信息
                        }
                    } else {
                        result.error("INVALID_ARGS", "startDownloadSelected 缺少参数 (topCid, localBasePath, or selectedPaths)", null)
                    }
                }

                "queryDownloadProgress" -> {
                    val downloadID = call.argument<String>("downloadID")
                    if (downloadID != null) {
                        try {
                            // 调用 Go 函数，现在返回 JSON 字符串
                            val jsonString = Libgopeed.queryDownloadProgress(downloadID)
                            // 解析 JSON 字符串为 Map<String, Any?>
                            val jsonObj = JSONObject(jsonString)
                            val resultMap = mutableMapOf<String, Any?>()
                            val keys = jsonObj.keys()
                            while (keys.hasNext()) {
                                val key = keys.next()
                                resultMap[key] = jsonObj.get(key)
                            }
                             // 确保数值类型正确 (可选，取决于 Dart 端如何处理)
                            resultMap["totalBytes"] = jsonObj.getLong("totalBytes")
                            resultMap["bytesRetrieved"] = jsonObj.getLong("bytesRetrieved")
                            resultMap["speedBps"] = jsonObj.getDouble("speedBps")
                            resultMap["elapsedTimeSec"] = jsonObj.getDouble("elapsedTimeSec")

                            result.success(resultMap)
                        } catch (e: Exception) {
                            result.error("IPFS_QUERY_PROGRESS_ERROR", e.localizedMessage ?: "查询进度失败", e.toString()) // 添加详细错误信息
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
