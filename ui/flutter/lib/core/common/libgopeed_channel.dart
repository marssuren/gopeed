import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:gopeed/core/common/ipfs/directory_entry.dart';
import 'package:gopeed/core/common/ipfs/progress_info.dart';

import 'libgopeed_interface.dart';
import 'start_config.dart';

class LibgopeedChannel implements LibgopeedInterface {
  static const _channel = MethodChannel('gopeed.com/libgopeed');

  @override
  Future<int> start(StartConfig cfg) async {
    final port = await _channel.invokeMethod('start', {
      'cfg': jsonEncode(cfg),
    });
    return port as int;
  }

  @override
  Future<void> stop() async {
    return await _channel.invokeMethod('stop');
  }

  @override
  Future<bool> initIPFS(String repoPath) async {
    try {
      final bool? success =
          await _channel.invokeMethod('initIPFS', {'repoPath': repoPath});
      // 需要处理可能的 null 情况，尽管原生端应该返回 bool
      return success ?? false;
    } on PlatformException catch (e) {
      print("Error initializing IPFS: ${e.code} - ${e.message}");
      rethrow; // 或者返回 false / 抛出自定义异常
    }
  }

  @override
  Future<String> startIPFS(String repoPath) async {
    try {
      final String? peerId =
          await _channel.invokeMethod('startIPFS', {'repoPath': repoPath});
      // 需要处理可能的 null 情况
      return peerId ?? (throw Exception("Failed to get Peer ID from native"));
    } on PlatformException catch (e) {
      print("Error starting IPFS: ${e.code} - ${e.message}");
      rethrow; // 或者返回空字符串 / 抛出自定义异常
    }
  }

  @override
  Future<void> stopIPFS() async {
    try {
      await _channel.invokeMethod('stopIPFS');
    } on PlatformException catch (e) {
      print("Error stopping IPFS: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<String> addFileToIPFS(String content) async {
    try {
      final String? cid =
          await _channel.invokeMethod('addFileToIPFS', {'content': content});
      return cid ?? (throw Exception("Failed to get CID from native"));
    } on PlatformException catch (e) {
      print("Error adding file to IPFS: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<String> addFileToIPFS2(String content) async {
    try {
      final String? cid =
          await _channel.invokeMethod('addFileToIPFS2', {'content': content});
      return cid ?? (throw Exception("Failed to get CID from native"));
    } on PlatformException catch (e) {
      print("Error adding file to IPFS: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<Uint8List> getFileFromIPFS(String cid) async {
    try {
      final Uint8List? fileContent =
          await _channel.invokeMethod('getFileFromIPFS', {'cid': cid});
      return fileContent ??
          (throw Exception("Failed to get file content from native"));
    } on PlatformException catch (e) {
      print("Error getting file from IPFS: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<String> getIPFSPeerID() async {
    try {
      final String? peerId = await _channel.invokeMethod('getIPFSPeerID');
      return peerId ?? (throw Exception("Failed to get Peer ID from native"));
    } on PlatformException catch (e) {
      print("Error getting IPFS Peer ID: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<List<DirectoryEntry>> listDirectoryFromIPFS(String cid) async {
    try {
      // Kotlin 端应该返回 List<Map<String, dynamic>>
      final List<dynamic>? result =
          await _channel.invokeMethod('listDirectoryFromIPFS', {'cid': cid});
      if (result == null) {
        throw Exception("Native 'listDirectoryFromIPFS' returned null list");
      }
      // 将 List<dynamic> (实际是 List<Map<String, dynamic>>) 转换为 List<DirectoryEntry>
      final entries = result
          .map((item) =>
              DirectoryEntry.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      return entries;
    } on PlatformException catch (e) {
      print("Error listing directory from IPFS: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      // 捕获可能的类型转换错误
      print("Error processing result from 'listDirectoryFromIPFS': $e");
      rethrow;
    }
  }

  @override
  Future<String> startDownloadSelected(
      String topCid, String localBasePath, List<String> selectedPaths) async {
    try {
      final String? taskId =
          await _channel.invokeMethod('startDownloadSelected', {
        'topCid': topCid,
        'localBasePath': localBasePath,
        'selectedPaths': selectedPaths,
      });
      return taskId ??
          (throw Exception(
              "Native 'startDownloadSelected' returned null task ID"));
    } on PlatformException catch (e) {
      print("Error starting selected download: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<ProgressInfo> queryDownloadProgress(String downloadID) async {
    try {
      // Kotlin 端应该返回 Map<String, dynamic>
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod('queryDownloadProgress', {'downloadID': downloadID});
      if (result == null) {
        throw Exception("Native 'queryDownloadProgress' returned null map");
      }
      // 将 Map<dynamic, dynamic> 转换为 Map<String, dynamic> 再创建对象
      return ProgressInfo.fromJson(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      print("Error querying download progress: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      // 捕获可能的类型转换错误
      print("Error processing result from 'queryDownloadProgress': $e");
      rethrow;
    }
  }
}
