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

  Future<List<DirectoryEntry>> listDirectoryFromIPFS(String cid);
  Future<String> startDownloadSelected(String topCid, String localBasePath, List<String> selectedPaths);
  Future<ProgressInfo> queryDownloadProgress(String downloadID);
}
