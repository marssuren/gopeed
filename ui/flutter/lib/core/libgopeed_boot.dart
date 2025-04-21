import 'dart:typed_data';

import 'common/start_config.dart';
import "libgopeed_boot_stub.dart"
    if (dart.library.html) 'entry/libgopeed_boot_browser.dart'
    if (dart.library.io) 'entry/libgopeed_boot_native.dart';

abstract class LibgopeedBoot {
  static LibgopeedBoot? _instance;

  static LibgopeedBoot get instance {
    _instance ??= LibgopeedBoot();
    return _instance!;
  }

  factory LibgopeedBoot() => create();

  Future<int> start(StartConfig cfg);

  Future<void> stop();

  Future<bool> initIPFS(String repoPath);
  Future<String> startIPFS(String repoPath);
  Future<void> stopIPFS();
  Future<String> addFileToIPFS(String content);
  Future<Uint8List> getFileFromIPFS(String cid);
  Future<String> getIPFSPeerID();

  Future<String> listDirectoryFromIPFS(String cid);
  Future<String> startDownloadSelected(
      String topCid, String localBasePath, String selectedPathsJson);
  Future<String> queryDownloadProgress(String downloadID);

  Future<void> downloadAndSaveFile(
      String cid, String localFilePath, String downloadID);
  Future<String> getIpfsNodeInfo(String cid);

  Future<String> startHTTPServices({int apiPort = 0, int gatewayPort = 0});
  Future<void> stopHTTPServices();
}
