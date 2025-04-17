import 'dart:typed_data';

import 'package:gopeed/core/common/ipfs/directory_entry.dart';
import 'package:gopeed/core/common/ipfs/progress_info.dart';

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

  Future<List<DirectoryEntry>> listDirectoryFromIPFS(String cid);
  Future<String> startDownloadSelected(String topCid, String localBasePath, List<String> selectedPaths);
  Future<ProgressInfo> queryDownloadProgress(String downloadID);
}
