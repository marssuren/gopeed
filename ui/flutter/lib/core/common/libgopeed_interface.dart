import 'dart:typed_data';

import 'package:gopeed/core/common/ipfs/directory_entry.dart';
import 'package:gopeed/core/common/ipfs/progress_info.dart';

import 'start_config.dart';

abstract class LibgopeedInterface {
  Future<int> start(StartConfig cfg);

  Future<void> stop();

  Future<bool> initIPFS(String repoPath);
  Future<String> startIPFS(String repoPath);
  Future<void> stopIPFS();
  Future<String> addFileToIPFS(String content);
  Future<Uint8List> getFileFromIPFS(String cid);
  Future<String> getIPFSPeerID();

  Future<String> listDirectoryFromIPFS(String cid);
  Future<String> startDownloadSelected(String topCid, String localBasePath, String selectedPathsJson);
  Future<String> queryDownloadProgress(String downloadID);
  Future<void> downloadAndSaveFile(String cid, String localFilePath, String downloadID);
  Future<String> getIpfsNodeInfo(String cid);
  
  // 启动 HTTP 服务，可选指定 API 端口和网关端口（0表示使用默认值）
  Future<String> startHTTPServices({int apiPort = 0, int gatewayPort = 0});
  Future<void> stopHTTPServices();
}
