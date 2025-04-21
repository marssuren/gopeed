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
  Future<String> listDirectoryFromIPFS(String cid) async {
    try {
      final String? jsonString =
          await _channel.invokeMethod('listDirectoryFromIPFS', {'cid': cid});
      if (jsonString == null || jsonString.isEmpty) {
        return '[]';
      }
      return jsonString;
    } on PlatformException catch (e) {
      print("Error listing directory from IPFS: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<String> startDownloadSelected(
      String topCid, String localBasePath, String selectedPathsJson) async {
    try {
      final String? taskId =
          await _channel.invokeMethod('startDownloadSelected', {
        'topCid': topCid,
        'localBasePath': localBasePath,
        'selectedPaths': selectedPathsJson,
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
  Future<String> queryDownloadProgress(String downloadID) async {
    try {
      final String? jsonString = await _channel
          .invokeMethod('queryDownloadProgress', {'downloadID': downloadID});
      if (jsonString == null || jsonString.isEmpty) {
        return '{}';
      }
      return jsonString;
    } on PlatformException catch (e) {
      print("Error querying download progress: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  // 实现 downloadAndSaveFile 方法
  @override
  Future<void> downloadAndSaveFile(
      String cid, String localFilePath, String downloadID) async {
    try {
      // 调用原生方法，它不返回数据，但可能抛出异常
      await _channel.invokeMethod('downloadAndSaveFile', {
        'cid': cid,
        'localFilePath': localFilePath,
        'downloadID': downloadID,
      });
    } on PlatformException catch (e) {
      print("Error downloading and saving file: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  @override
  Future<String> getIpfsNodeInfo(String cid) async {
    try {
      final String? jsonString =
          await _channel.invokeMethod('getIpfsNodeInfo', {'cid': cid});
      // Go 端设计为总返回字符串，但做个保护
      return jsonString ?? '{\"cid\":\"$cid\", \"type\":\"unknown\", \"error\":\"Native returned null unexpectedly\"}';
    } on PlatformException catch (e) {
      print("Error getting IPFS node info: ${e.code} - ${e.message}");
      // 返回包含错误的 JSON
      return '{\"cid\":\"$cid\", \"type\":\"unknown\", \"error\":\"PlatformException: ${e.code} - ${e.message}\"}';
    }
  }
}
