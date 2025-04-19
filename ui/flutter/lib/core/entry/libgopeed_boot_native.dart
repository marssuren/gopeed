import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:gopeed/core/common/ipfs/directory_entry.dart';
import 'package:gopeed/core/common/ipfs/progress_info.dart';

import '../../util/util.dart';
import '../common/libgopeed_channel.dart';
import '../common/libgopeed_ffi.dart';
import '../common/libgopeed_interface.dart';
import '../common/start_config.dart';
import '../ffi/libgopeed_bind.dart';
import '../libgopeed_boot.dart';

LibgopeedBoot create() => LibgopeedBootNative();

class LibgopeedBootNative implements LibgopeedBoot {
  late LibgopeedInterface _libgopeed;

  LibgopeedBootNative() {
    if (Util.isDesktop()) {
      var libName = "libgopeed.";
      if (Platform.isWindows) {
        libName += "dll";
      }
      if (Platform.isMacOS) {
        libName += "dylib";
      }
      if (Platform.isLinux) {
        libName += "so";
      }
      _libgopeed = LibgopeedFFi(LibgopeedBind(DynamicLibrary.open(libName)));
    } else {
      _libgopeed = LibgopeedChannel();
    }
  }

  @override
  Future<int> start(StartConfig cfg) async {
    cfg.storage = 'bolt';
    cfg.storageDir = Util.getStorageDir();
    cfg.refreshInterval = 0;
    var port = await _libgopeed.start(cfg);
    return port;
  }

  @override
  Future<void> stop() async {
    await _libgopeed.stop();
  }


  // IPFS
  @override
  Future<bool> initIPFS(String repoPath) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.initIPFS(repoPath);
  }

  @override
  Future<String> startIPFS(String repoPath) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.startIPFS(repoPath);
  }

  @override
  Future<void> stopIPFS() {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.stopIPFS();
  }

  @override
  Future<String> addFileToIPFS(String content) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.addFileToIPFS(content);
  }

  @override
  Future<Uint8List> getFileFromIPFS(String cid) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.getFileFromIPFS(cid);
  }

  @override
  Future<String> getIPFSPeerID() {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.getIPFSPeerID();
  }

  
  @override
  Future<String> listDirectoryFromIPFS(String cid) {
    // 将调用委托给内部的 _libgopeed 实例
    var result = _libgopeed.listDirectoryFromIPFS(cid);
    return _libgopeed.listDirectoryFromIPFS(cid);
  }

  @override
  Future<String> startDownloadSelected(String topCid, String localBasePath, String selectedPathsJson) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.startDownloadSelected(topCid, localBasePath, selectedPathsJson);
  }

  @override
  Future<String> queryDownloadProgress(String downloadID) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.queryDownloadProgress(downloadID);
  }

  // 添加 downloadAndSaveFile 方法实现
  @override
  Future<void> downloadAndSaveFile(String cid, String localFilePath, String downloadID) {
    // 将调用委托给内部的 _libgopeed 实例
    return _libgopeed.downloadAndSaveFile(cid, localFilePath, downloadID);
  }
}
