import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:gopeed/core/common/ipfs/directory_entry.dart';
import 'package:gopeed/core/common/ipfs/progress_info.dart';

import '../ffi/libgopeed_bind.dart';
import 'libgopeed_interface.dart';
import 'start_config.dart';

class LibgopeedFFi implements LibgopeedInterface {
  late LibgopeedBind _libgopeed;

  LibgopeedFFi(LibgopeedBind libgopeed) {
    _libgopeed = libgopeed;
  }

  @override
  Future<int> start(StartConfig cfg) {
    var completer = Completer<int>();
    var result = _libgopeed.Start(jsonEncode(cfg).toNativeUtf8().cast());
    if (result.r1 != nullptr) {
      completer.completeError(Exception(result.r1.cast<Utf8>().toDartString()));
    } else {
      completer.complete(result.r0);
    }
    return completer.future;
  }

  @override
  Future<void> stop() {
    var completer = Completer<void>();
    _libgopeed.Stop();
    completer.complete();
    return completer.future;
  }

  @override
  Future<String> addFileToIPFS(String content) {
    // TODO: implement addFileToIPFS
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> getFileFromIPFS(String cid) {
    // TODO: implement getFileFromIPFS
    throw UnimplementedError();
  }

  @override
  Future<String> getIPFSPeerID() {
    // TODO: implement getIPFSPeerID
    throw UnimplementedError();
  }

  @override
  Future<bool> initIPFS(String repoPath) {
    // TODO: implement initIPFS
    throw UnimplementedError();
  }

  @override
  Future<String> startIPFS(String repoPath) {
    // TODO: implement startIPFS
    throw UnimplementedError();
  }

  @override
  Future<void> stopIPFS() {
    // TODO: implement stopIPFS
    throw UnimplementedError();
  }

  @override
  Future<String> listDirectoryFromIPFS(String cid) {
    // TODO: implement listDirectoryFromIPFS
    throw UnimplementedError();
  }

  @override
  Future<String> queryDownloadProgress(String downloadID) {
    // TODO: implement queryDownloadProgress
    throw UnimplementedError();
  }

  @override
  Future<String> startDownloadSelected(String topCid, String localBasePath, String selectedPathsJson) {
    // TODO: implement startDownloadSelected
    throw UnimplementedError();
  }

  @override
  Future<void> downloadAndSaveFile(String cid, String localFilePath, String downloadID) {
    // TODO: implement downloadAndSaveFile
    throw UnimplementedError();
  }

  @override
  Future<String> getIpfsNodeInfo(String cid) {
    // TODO: implement getIpfsNodeInfo
    throw UnimplementedError();
  }

  @override
  Future<String> startHTTPServices({int apiPort = 0, int gatewayPort = 0}) {
    // TODO: implement startHTTPServices
    throw UnimplementedError();
  }

  @override
  Future<void> stopHTTPServices() {
    // TODO: implement stopHTTPServices
    throw UnimplementedError();
  }
}
