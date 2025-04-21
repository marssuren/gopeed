import 'dart:convert';
import 'dart:typed_data';  // 添加Uint8List支持

import 'package:contentsize_tabbarview/contentsize_tabbarview.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gopeed/core/libgopeed_boot.dart';
import 'package:gopeed/util/log_util.dart';
import 'package:path/path.dart' as path;
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:path_provider/path_provider.dart'; 
import 'dart:io'; 
import 'dart:async'; // 导入 Timer
import 'dart:convert'; // 导入 jsonDecode

import '../../../../api/api.dart';
import '../../../../api/model/create_task.dart';
import '../../../../api/model/create_task_batch.dart';
import '../../../../api/model/options.dart';
import '../../../../api/model/request.dart';
import '../../../../api/model/resolve_result.dart';
import '../../../../api/model/task.dart';
import '../../../../database/database.dart';
import '../../../../util/input_formatter.dart';
import '../../../../util/message.dart';
import '../../../../util/util.dart';
import '../../../routes/app_pages.dart';
import '../../../views/compact_checkbox.dart';
import '../../../views/directory_selector.dart';
import '../../../views/file_tree_view.dart';
import '../../app/controllers/app_controller.dart';
import '../../history/views/history_view.dart';
import '../controllers/create_controller.dart';
import '../dto/create_router_params.dart';
import '../../../../core/common/ipfs/directory_entry.dart';  // 添加DirectoryEntry引用
import '../../../../core/common/ipfs/progress_info.dart'; // 导入 ProgressInfo

class CreateView extends GetView<CreateController> {
  final _confirmFormKey = GlobalKey<FormState>();

  final _urlController = TextEditingController();
  final _renameController = TextEditingController();
  final _connectionsController = TextEditingController();
  final _pathController = TextEditingController();
  final _confirmController = RoundedLoadingButtonController();
  final _proxyIpController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _proxyUsrController = TextEditingController();
  final _proxyPwdController = TextEditingController();
  final _httpHeaderControllers = [
    (
      name: TextEditingController(text: "User-Agent"),
      value: TextEditingController()
    ),
    (
      name: TextEditingController(text: "Cookie"),
      value: TextEditingController()
    ),
    (
      name: TextEditingController(text: "Referer"),
      value: TextEditingController()
    ),
  ];
  final _btTrackerController = TextEditingController();

  final _availableSchemes = ["http:", "https:", "magnet:"];

  final _skipVerifyCertController = false.obs;

  CreateView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appController = Get.find<AppController>();

    if (_connectionsController.text.isEmpty) {
      _connectionsController.text = appController
          .downloaderConfig.value.protocolConfig.http.connections
          .toString();
    }
    if (_pathController.text.isEmpty) {
      _pathController.text = appController.downloaderConfig.value.downloadDir;
    }

    final CreateRouterParams? routerParams = Get.rootDelegate.arguments();
    if (routerParams?.req?.url.isNotEmpty ?? false) {
      // get url from route arguments
      final url = routerParams!.req!.url;
      _urlController.text = url;
      _urlController.selection = TextSelection.fromPosition(
          TextPosition(offset: _urlController.text.length));
      final protocol = parseProtocol(url);
      if (protocol != null) {
        final extraHandlers = {
          Protocol.http: () {
            final reqExtra = ReqExtraHttp.fromJson(
                jsonDecode(jsonEncode(routerParams.req!.extra)));
            _httpHeaderControllers.clear();
            reqExtra.header.forEach((key, value) {
              _httpHeaderControllers.add(
                (
                  name: TextEditingController(text: key),
                  value: TextEditingController(text: value),
                ),
              );
            });
            _skipVerifyCertController.value = routerParams.req!.skipVerifyCert;
          },
          Protocol.bt: () {
            final reqExtra = ReqExtraBt.fromJson(
                jsonDecode(jsonEncode(routerParams.req!.extra)));
            _btTrackerController.text = reqExtra.trackers.join("\n");
          },
        };
        if (routerParams.req?.extra != null) {
          extraHandlers[protocol]?.call();
        }

        // handle options
        if (routerParams.opt != null) {
          _renameController.text = routerParams.opt!.name;
          _pathController.text = routerParams.opt!.path;

          final optionsHandlers = {
            Protocol.http: () {
              final opt = routerParams.opt!;
              _renameController.text = opt.name;
              _pathController.text = opt.path;
              if (opt.extra != null) {
                final optsExtraHttp =
                    OptsExtraHttp.fromJson(jsonDecode(jsonEncode(opt.extra)));
                _connectionsController.text =
                    optsExtraHttp.connections.toString();
              }
            },
            Protocol.bt: null,
          };
          if (routerParams.opt?.extra != null) {
            optionsHandlers[protocol]?.call();
          }
        }
      }
    } else if (_urlController.text.isEmpty) {
      // read clipboard
      Clipboard.getData('text/plain').then((value) {
        if (value?.text?.isNotEmpty ?? false) {
          if (_availableSchemes
              .where((e) =>
                  value!.text!.startsWith(e) ||
                  value.text!.startsWith(e.toUpperCase()))
              .isNotEmpty) {
            _urlController.text = value!.text!;
            _urlController.selection = TextSelection.fromPosition(
                TextPosition(offset: _urlController.text.length));
            return;
          }

          recognizeMagnetUri(value!.text!);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Get.rootDelegate.offNamed(Routes.TASK)),
        // actions: [],
        title: Text('create'.tr),
      ),
      body: DropTarget(
        onDragDone: (details) async {
          if (!Util.isWeb()) {
            _urlController.text = details.files[0].path;
            return;
          }
          _urlController.text = details.files[0].name;
          final bytes = await details.files[0].readAsBytes();
          controller.setFileDataUri(bytes);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            FocusScope.of(context).requestFocus(FocusNode());
          },
          child: SingleChildScrollView(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
              child: Form(
                key: _confirmFormKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          autofocus: !Util.isMobile(),
                          controller: _urlController,
                          minLines: 1,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: _hitText(),
                            hintStyle: const TextStyle(fontSize: 12),
                            labelText: 'downloadLink'.tr,
                            icon: const Icon(Icons.link),
                            suffixIcon: IconButton(
                              onPressed: () {
                                _urlController.clear();
                                controller.clearFileDataUri();
                              },
                              icon: const Icon(Icons.clear),
                            ),
                          ),
                          validator: (v) {
                            return v!.trim().isNotEmpty
                                ? null
                                : 'downloadLinkValid'.tr;
                          },
                          onChanged: (v) async {
                            controller.clearFileDataUri();
                            if (controller.oldUrl.value.isEmpty) {
                              recognizeMagnetUri(v);
                            }
                            controller.oldUrl.value = v;
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: () async {
                          var pr = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ["torrent"]);
                          if (pr != null) {
                            if (!Util.isWeb()) {
                              _urlController.text = pr.files[0].path ?? "";
                              return;
                            }
                            _urlController.text = pr.files[0].name;
                            controller.setFileDataUri(pr.files[0].bytes!);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.history_rounded),
                        onPressed: () async {
                          List<String> resultOfHistories =
                              Database.instance.getCreateHistory() ?? [];
                          // show dialog box to list history
                          if (context.mounted) {
                            showGeneralDialog(
                              barrierColor: Colors.black.withOpacity(0.5),
                              transitionBuilder: (context, a1, a2, widget) {
                                return Transform.scale(
                                  scale: a1.value,
                                  child: Opacity(
                                    opacity: a1.value,
                                    child: HistoryView(
                                      isHistoryListEmpty:
                                          resultOfHistories.isEmpty,
                                      historyList: ListView.builder(
                                        itemCount: resultOfHistories.length,
                                        itemBuilder: (context, index) {
                                          return GestureDetector(
                                            onTap: () {
                                              _urlController.text =
                                                  resultOfHistories[index];
                                              Navigator.pop(context);
                                            },
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8.0,
                                                  vertical: 8.0,
                                                ),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10.0,
                                                  vertical: 8.0,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surface,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10.0),
                                                ),
                                                child: Text(
                                                  resultOfHistories[index],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                              transitionDuration:
                                  const Duration(milliseconds: 250),
                              barrierDismissible: true,
                              barrierLabel: '',
                              context: context,
                              pageBuilder: (context, animation1, animation2) {
                                return const Text('PAGE BUILDER');
                              },
                            );
                          }
                        },
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: Column(children: [
                        TextField(
                          controller: _renameController,
                          decoration: InputDecoration(labelText: 'rename'.tr),
                        ),
                        TextField(
                          controller: _connectionsController,
                          decoration: InputDecoration(
                            labelText: 'connections'.tr,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            NumericalRangeFormatter(min: 1, max: 256),
                          ],
                        ),
                        DirectorySelector(
                          controller: _pathController,
                        ),
                        Obx(
                          () => Visibility(
                            visible: controller.showAdvanced.value,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Transform.translate(
                                      offset: const Offset(-40, 0),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.wifi_2_bar,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(
                                            width: 15,
                                          ),
                                          SizedBox(
                                              width: 150,
                                              child: DropdownButton<
                                                  RequestProxyMode>(
                                                hint: Text('proxy'.tr),
                                                isExpanded: true,
                                                value: controller
                                                    .proxyConfig.value?.mode,
                                                onChanged: (value) async {
                                                  if (value != null) {
                                                    controller.proxyConfig
                                                        .value = RequestProxy()
                                                      ..mode = value;
                                                  }
                                                },
                                                items: [
                                                  DropdownMenuItem<
                                                      RequestProxyMode>(
                                                    value:
                                                        RequestProxyMode.follow,
                                                    child: Text(
                                                        'followSettings'.tr),
                                                  ),
                                                  DropdownMenuItem<
                                                      RequestProxyMode>(
                                                    value:
                                                        RequestProxyMode.none,
                                                    child: Text('noProxy'.tr),
                                                  ),
                                                  DropdownMenuItem<
                                                      RequestProxyMode>(
                                                    value:
                                                        RequestProxyMode.custom,
                                                    child:
                                                        Text('customProxy'.tr),
                                                  ),
                                                ],
                                              ))
                                        ],
                                      ),
                                    ),
                                    ...(controller.proxyConfig.value?.mode ==
                                            RequestProxyMode.custom
                                        ? [
                                            SizedBox(
                                              width: 150,
                                              child: DropdownButtonFormField<
                                                  String>(
                                                value: controller
                                                    .proxyConfig.value?.scheme,
                                                onChanged: (value) async {
                                                  if (value != null) {}
                                                },
                                                items: const [
                                                  DropdownMenuItem<String>(
                                                    value: 'http',
                                                    child: Text('HTTP'),
                                                  ),
                                                  DropdownMenuItem<String>(
                                                    value: 'https',
                                                    child: Text('HTTPS'),
                                                  ),
                                                  DropdownMenuItem<String>(
                                                    value: 'socks5',
                                                    child: Text('SOCKS5'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Row(children: [
                                              Flexible(
                                                child: TextFormField(
                                                  controller:
                                                      _proxyIpController,
                                                  decoration: InputDecoration(
                                                    labelText: 'server'.tr,
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            0.0),
                                                  ),
                                                ),
                                              ),
                                              const Padding(
                                                  padding: EdgeInsets.only(
                                                      left: 10)),
                                              Flexible(
                                                child: TextFormField(
                                                  controller:
                                                      _proxyPortController,
                                                  decoration: InputDecoration(
                                                    labelText: 'port'.tr,
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            0.0),
                                                  ),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                    NumericalRangeFormatter(
                                                        min: 0, max: 65535),
                                                  ],
                                                ),
                                              ),
                                            ]),
                                            Row(children: [
                                              Flexible(
                                                child: TextFormField(
                                                  controller:
                                                      _proxyUsrController,
                                                  decoration: InputDecoration(
                                                    labelText: 'username'.tr,
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            0.0),
                                                  ),
                                                ),
                                              ),
                                              const Padding(
                                                  padding: EdgeInsets.only(
                                                      left: 10)),
                                              Flexible(
                                                child: TextFormField(
                                                  controller:
                                                      _proxyPwdController,
                                                  decoration: InputDecoration(
                                                    labelText: 'password'.tr,
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            0.0),
                                                  ),
                                                ),
                                              ),
                                            ])
                                          ]
                                        : const []),
                                  ],
                                ),
                                const Divider(),
                                TabBar(
                                  controller: controller.advancedTabController,
                                  tabs: const [
                                    Tab(
                                      text: 'HTTP',
                                    ),
                                    Tab(
                                      text: 'BitTorrent',
                                    )
                                  ],
                                ),
                                DefaultTabController(
                                  length: 2,
                                  child: ContentSizeTabBarView(
                                    controller:
                                        controller.advancedTabController,
                                    children: [
                                      Column(
                                        children: [
                                          ..._httpHeaderControllers.map((e) {
                                            return Row(
                                              children: [
                                                Flexible(
                                                  child: TextFormField(
                                                    controller: e.name,
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'httpHeaderName'.tr,
                                                    ),
                                                  ),
                                                ),
                                                const Padding(
                                                    padding: EdgeInsets.only(
                                                        left: 10)),
                                                Flexible(
                                                  child: TextFormField(
                                                    controller: e.value,
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'httpHeaderValue'.tr,
                                                    ),
                                                  ),
                                                ),
                                                const Padding(
                                                    padding: EdgeInsets.only(
                                                        left: 10)),
                                                IconButton(
                                                  icon: const Icon(Icons.add),
                                                  onPressed: () {
                                                    _httpHeaderControllers.add(
                                                      (
                                                        name:
                                                            TextEditingController(),
                                                        value:
                                                            TextEditingController(),
                                                      ),
                                                    );
                                                    controller.showAdvanced
                                                        .update((val) => val);
                                                  },
                                                ),
                                                IconButton(
                                                  icon:
                                                      const Icon(Icons.remove),
                                                  onPressed: () {
                                                    if (_httpHeaderControllers
                                                            .length <=
                                                        1) {
                                                      return;
                                                    }
                                                    _httpHeaderControllers
                                                        .remove(e);
                                                    controller.showAdvanced
                                                        .update((val) => val);
                                                  },
                                                ),
                                              ],
                                            );
                                          }),
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 10),
                                            child: CompactCheckbox(
                                              label: 'skipVerifyCert'.tr,
                                              value: _skipVerifyCertController
                                                  .value,
                                              onChanged: (bool? value) {
                                                _skipVerifyCertController
                                                    .value = value ?? false;
                                              },
                                              textStyle: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Column(
                                        children: [
                                          TextFormField(
                                              controller: _btTrackerController,
                                              maxLines: 5,
                                              decoration: InputDecoration(
                                                labelText: 'Trackers',
                                                hintText: 'addTrackerHit'.tr,
                                              )),
                                        ],
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ).paddingOnly(top: 16),
                          ),
                        ),
                      ]),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CompactCheckbox(
                                    label: 'directDownload'.tr,
                                    value: controller.directDownload.value,
                                    onChanged: (bool? value) {
                                      controller.directDownload.value =
                                          value ?? false;
                                    }),
                                TextButton(
                                  onPressed: () {
                                    controller.showAdvanced.value =
                                        !controller.showAdvanced.value;
                                  },
                                  child: Row(children: [
                                    Obx(() => Checkbox(
                                          value: controller.showAdvanced.value,
                                          onChanged: (bool? value) {
                                            controller.showAdvanced.value =
                                                value ?? false;
                                          },
                                        )),
                                    Text('advancedOptions'.tr),
                                  ]),
                                ),
                              ],
                            ),
                            SizedBox(
                              width: 150,
                              child: RoundedLoadingButton(
                                color: Get.theme.colorScheme.secondary,
                                onPressed: _doConfirm,
                                controller: _confirmController,
                                child: Text('confirm'.tr),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.cloud_outlined),
                                  label: Text('IPFS测试'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                              onPressed: (){
                                _showIpfsDownloadDialog(context);
                              },
                            ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.file_download_outlined),
                                  label: Text('单文件测试'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: (){
                                    _showSimpleFileDownloadDialog(context);
                              },
                            ),
                          ],
                        ),
                            // 新增按钮：测试单文件保存
                            Padding(
                              padding: const EdgeInsets.only(top: 10.0), // 加一点间距
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.save_alt),
                                label: Text('单文件保存测试'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  _showSingleFileSaveDialog(context);
                                },
                              ),
                            ),
                            // 新增按钮：获取 IPFS 节点信息
                            Padding(
                              padding: const EdgeInsets.only(top: 10.0), 
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.info_outline),
                                label: Text('获取节点信息'), 
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  _showIpfsInfoDialog(context);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSimpleFileDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return const SimpleFileDownloadDialog();
      },
    );
  }

  void _showIpfsDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // 使用 StatefulWidget 来管理 TextEditingController
        return const IpfsDownloadDialog();
      },
    );
  }

  // parse protocol from url
  parseProtocol(String url) {
    final uppercaseUrl = url.toUpperCase();
    Protocol? protocol;
    if (uppercaseUrl.startsWith("HTTP:") || uppercaseUrl.startsWith("HTTPS:")) {
      protocol = Protocol.http;
    }
    if (uppercaseUrl.startsWith("MAGNET:") ||
        uppercaseUrl.endsWith(".TORRENT")) {
      protocol = Protocol.bt;
    }
    return protocol;
  }

  // recognize magnet uri, if length == 40, auto add magnet prefix
  recognizeMagnetUri(String text) {
    if (text.length != 40) {
      return;
    }
    final exp = RegExp(r"[0-9a-fA-F]+");
    if (exp.hasMatch(text)) {
      final uri = "magnet:?xt=urn:btih:$text";
      _urlController.text = uri;
      _urlController.selection = TextSelection.fromPosition(
          TextPosition(offset: _urlController.text.length));
    }
  }

  Future<void> _doConfirm() async {
    if (controller.isConfirming.value) {
      return;
    }
    controller.isConfirming.value = true;
    try {
      _confirmController.start();
      if (_confirmFormKey.currentState!.validate()) {
        final isWebFileChosen =
            Util.isWeb() && controller.fileDataUri.isNotEmpty;
        final submitUrl = isWebFileChosen
            ? controller.fileDataUri.value
            : _urlController.text.trim();

        final urls = Util.textToLines(submitUrl);
        // Add url to the history
        if (!isWebFileChosen) {
          for (final url in urls) {
            Database.instance.saveCreateHistory(url);
          }
        }

        /*
        Check if is direct download, there has two ways to direct download
        1. Direct download option is checked
        2. Muli line urls
        */
        final isMultiLine = urls.length > 1;
        final isDirect = controller.directDownload.value || isMultiLine;
        if (isDirect) {
          await Future.wait(urls.map((url) {
            return createTask(CreateTask(
                req: Request(
                  url: url,
                  extra: parseReqExtra(url),
                  proxy: parseProxy(),
                  skipVerifyCert: _skipVerifyCertController.value,
                ),
                opt: Options(
                  name: isMultiLine ? "" : _renameController.text,
                  path: _pathController.text,
                  selectFiles: [],
                  extra: parseReqOptsExtra(),
                )));
          }));
          Get.rootDelegate.offNamed(Routes.TASK);
        } else {
          final rr = await resolve(Request(
            url: submitUrl,
            extra: parseReqExtra(_urlController.text),
            proxy: parseProxy(),
            skipVerifyCert: _skipVerifyCertController.value,
          ));
          await _showResolveDialog(rr);
        }
      }
    } catch (e) {
      showErrorMessage(e);
    } finally {
      _confirmController.reset();
      controller.isConfirming.value = false;
    }
  }

  RequestProxy? parseProxy() {
    if (controller.proxyConfig.value?.mode == RequestProxyMode.custom) {
      return RequestProxy()
        ..mode = RequestProxyMode.custom
        ..scheme = _proxyIpController.text
        ..host = "${_proxyIpController.text}:${_proxyPortController.text}"
        ..usr = _proxyUsrController.text
        ..pwd = _proxyPwdController.text;
    }
    return controller.proxyConfig.value;
  }

  Object? parseReqExtra(String url) {
    Object? reqExtra;
    final protocol = parseProtocol(url);
    switch (protocol) {
      case Protocol.http:
        final header = Map<String, String>.fromEntries(_httpHeaderControllers
            .map((e) => MapEntry(e.name.text, e.value.text)));
        header.removeWhere(
            (key, value) => key.trim().isEmpty || value.trim().isEmpty);
        if (header.isNotEmpty) {
          reqExtra = ReqExtraHttp()..header = header;
        }
        break;
      case Protocol.bt:
        if (_btTrackerController.text.trim().isNotEmpty) {
          reqExtra = ReqExtraBt()
            ..trackers = Util.textToLines(_btTrackerController.text);
        }
        break;
    }
    return reqExtra;
  }

  Object? parseReqOptsExtra() {
    return OptsExtraHttp()
      ..connections = int.tryParse(_connectionsController.text) ?? 0
      ..autoTorrent = true;
  }

  String _hitText() {
    return 'downloadLinkHit'.trParams({
      'append':
          Util.isDesktop() || Util.isWeb() ? 'downloadLinkHitDesktop'.tr : '',
    });
  }

  Future<void> _showResolveDialog(ResolveResult rr) async {
    final createFormKey = GlobalKey<FormState>();
    final downloadController = RoundedLoadingButtonController();
    return showDialog<void>(
        context: Get.context!,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
              title: rr.res.name.isEmpty ? null : Text(rr.res.name),
              content: Builder(
                builder: (context) {
                  // Get available height and width of the build area of this widget. Make a choice depending on the size.
                  var height = MediaQuery.of(context).size.height;
                  var width = MediaQuery.of(context).size.width;

                  return SizedBox(
                    height: height * 0.75,
                    width: width,
                    child: Form(
                        key: createFormKey,
                        autovalidateMode: AutovalidateMode.always,
                        child: FileTreeView(
                          files: rr.res.files,
                          initialValues: rr.res.files.asMap().keys.toList(),
                          onSelectionChanged: (List<int> values) {
                            controller.selectedIndexes.value = values;
                          },
                        )),
                  );
                },
              ),
              actions: [
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(
                    width: Get.theme.buttonTheme.minWidth,
                    height: Get.theme.buttonTheme.height,
                  ),
                  child: ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(shape: const StadiumBorder())
                            .copyWith(
                                backgroundColor: MaterialStateProperty.all(
                                    Get.theme.colorScheme.background)),
                    onPressed: () {
                      Get.back();
                    },
                    child: Text('cancel'.tr),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(
                    width: Get.theme.buttonTheme.minWidth,
                    height: Get.theme.buttonTheme.height,
                  ),
                  child: RoundedLoadingButton(
                      color: Get.theme.colorScheme.secondary,
                      onPressed: () async {
                        try {
                          downloadController.start();
                          if (controller.selectedIndexes.isEmpty) {
                            showMessage('tip'.tr, 'noFileSelected'.tr);
                            return;
                          }
                          final optExtra = parseReqOptsExtra();
                          if (createFormKey.currentState!.validate()) {
                            if (rr.id.isEmpty) {
                              // from extension resolve result
                              final reqs =
                                  controller.selectedIndexes.map((index) {
                                final file = rr.res.files[index];
                                return CreateTaskBatchItem(
                                    req: file.req!..proxy = parseProxy(),
                                    opts: Options(
                                        name: file.name,
                                        path: path.join(_pathController.text,
                                            rr.res.name, file.path),
                                        selectFiles: [],
                                        extra: optExtra));
                              }).toList();
                              await createTaskBatch(
                                  CreateTaskBatch(reqs: reqs));
                            } else {
                              await createTask(CreateTask(
                                  rid: rr.id,
                                  opt: Options(
                                      name: _renameController.text,
                                      path: _pathController.text,
                                      selectFiles: controller.selectedIndexes,
                                      extra: optExtra)));
                            }
                            Get.back();
                            Get.rootDelegate.offNamed(Routes.TASK);
                          }
                        } catch (e) {
                          showErrorMessage(e);
                        } finally {
                          downloadController.reset();
                        }
                      },
                      controller: downloadController,
                      child: Text(
                        'download'.tr,
                        // style: controller.selectedIndexes.isEmpty
                        //     ? Get.textTheme.disabled
                        //     : Get.textTheme.titleSmall
                      )),
                ),
              ],
            ));
  }

  // --- 新增：显示单文件保存测试对话框 ---
  void _showSingleFileSaveDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 下载时不允许点击外部关闭
      builder: (BuildContext dialogContext) {
        return const SingleFileSaveDialog(); // 指向我们即将创建的 Dialog Widget
      },
    );
  }

  // --- 新增：显示 IPFS 节点信息对话框 ---
  void _showIpfsInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return const IpfsInfoDialog(); // 指向我们即将创建的 Dialog Widget
      },
    );
  }
}


// --- 创建一个新的 StatefulWidget 作为对话框内容 ---
class IpfsDownloadDialog extends StatefulWidget {
  const IpfsDownloadDialog({Key? key}) : super(key: key);

  @override
  State<IpfsDownloadDialog> createState() => _IpfsDownloadDialogState();
}

class _IpfsDownloadDialogState extends State<IpfsDownloadDialog> {
  final TextEditingController _cidController = TextEditingController();
  bool _isLoading = false;
  String? _resultMessage; // 用于显示结果或错误
  List<DirectoryEntry>? _directoryEntries; // 存储目录结构
  String _currentCid = "";

  @override
  void initState() {
    super.initState();
    // 使用公开的IPFS目录CID样例 - IPFS项目文档
    _cidController.text = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";
    _currentCid = _cidController.text;
  }

  @override
  void dispose() {
    _cidController.dispose();
    super.dispose();
  }

  Future<void> _listIpfsDirectory() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty) {
      setState(() {
        _resultMessage = "请输入CID。";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
      _directoryEntries = null;
    });

    try {
      logger.i("尝试通过IPFS列出目录：$cid");
      // 现在 listDirectoryFromIPFS 返回 JSON 字符串
      var obj = await LibgopeedBoot.instance.listDirectoryFromIPFS(cid);
      final String entriesJson = await LibgopeedBoot.instance.listDirectoryFromIPFS(cid);
      logger.i("成功获取目录 JSON，CID: $cid, JSON: $entriesJson"); // 添加日志记录JSON内容

      // 使用 dart:convert 解析 JSON
      final List<dynamic> decodedList = jsonDecode(entriesJson);

      // 将解码后的 List<Map<String, dynamic>> 转换为 List<DirectoryEntry>
      final List<DirectoryEntry> entries = decodedList
          .map((item) => DirectoryEntry.fromJson(item as Map<String, dynamic>))
          .toList();

      logger.i("成功解析目录内容，共 ${entries.length} 个条目，CID: $cid");
      
      setState(() {
        _isLoading = false;
        _directoryEntries = entries; // 更新状态
        _currentCid = cid;
        _resultMessage = "目录加载成功，共${entries.length}个条目";
      });
    } on PlatformException catch (pe, stacktrace) { // 优先捕获 PlatformException
      logger.e("平台异常：无法获取或解析目录内容，CID: $cid", pe, stacktrace);
      setState(() {
        _isLoading = false;
        // 从 PlatformException 提取信息
        _resultMessage = "平台错误：\nCode: ${pe.code}\nMessage: ${pe.message}\nDetails: ${pe.details}";
      });
    } catch (e, stacktrace) { // 捕获其他可能的错误 (如 FormatException)
      logger.e("其他错误：无法获取或解析目录内容，CID: $cid", e, stacktrace);
      setState(() {
        _isLoading = false;
        // 对其他错误使用 toString()
        _resultMessage = "加载或解析失败：\n${e.toString()}"; 
      });
    }
  }

  Future<void> _downloadIpfsFile(String cid, bool isDirectory) async {
    if (cid.isEmpty) {
      setState(() {
        _resultMessage = "CID不能为空。";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      if (isDirectory) {
        // 如果是目录，就列出内容
        _cidController.text = cid;
        await _listIpfsDirectory();
      } else {
        // 如果是文件，就下载内容
        logger.i("尝试通过IPFS下载文件：$cid");
        final fileContent = await LibgopeedBoot.instance.getFileFromIPFS(cid);
        logger.i("成功下载内容，CID: $cid");
        setState(() {
          _isLoading = false;
          // 处理Uint8List类型的二进制数据
          String contentPreview;
          if (fileContent.length > 100) {
            // 尝试转换为文本，如果是文本文件
            try {
              contentPreview = utf8.decode(fileContent.sublist(0, 100), allowMalformed: true) + "...";
            } catch (e) {
              // 如果不是有效的UTF-8文本，就显示十六进制
              contentPreview = fileContent.sublist(0, 100).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ') + "...";
            }
          } else {
            try {
              contentPreview = utf8.decode(fileContent, allowMalformed: true);
            } catch (e) {
              contentPreview = fileContent.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
            }
          }
          _resultMessage = "下载成功！\n内容(部分)：$contentPreview";
        });
      }
    } catch (e) {
      logger.e("下载失败，CID: $cid", e);
      setState(() {
        _isLoading = false;
        _resultMessage = "下载失败：\n$e";
      });
    }
  }

  // 导航回上一级目录
  void _navigateBack() {
    if (_currentCid != _cidController.text.trim()) {
      _cidController.text = _currentCid;
      _listIpfsDirectory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('IPFS下载测试'),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cidController,
                    decoration: const InputDecoration(
                      labelText: '输入IPFS CID',
                      hintText: '例如 QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG',
                    ),
                    enabled: !_isLoading,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _isLoading ? null : _listIpfsDirectory,
                  tooltip: '加载目录',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_resultMessage != null && _directoryEntries == null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _resultMessage!,
                  style: TextStyle(
                    color: _resultMessage!.contains("失败") ? Colors.red : Colors.green,
                  ),
                ),
              )
            else if (_directoryEntries != null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text("当前CID: $_currentCid", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    if (_resultMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          _resultMessage!,
                          style: TextStyle(
                            color: _resultMessage!.contains("失败") ? Colors.red : Colors.green,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _directoryEntries!.length,
                        itemBuilder: (context, index) {
                          final entry = _directoryEntries![index];
                          return ListTile(
                            leading: Icon(
                              entry.type == "directory" ? Icons.folder : Icons.insert_drive_file,
                              color: entry.type == "directory" ? Colors.amber : Colors.blue,
                            ),
                            title: Text(entry.name),
                            subtitle: Text("${entry.type} - ${entry.size} bytes"),
                            trailing: IconButton(
                              icon: const Icon(Icons.download),
                              tooltip: entry.type == "directory" ? "打开目录" : "下载文件",
                              onPressed: () => _downloadIpfsFile(entry.cid, entry.type == "directory"),
                            ),
                            onTap: entry.type == "directory" 
                                ? () => _downloadIpfsFile(entry.cid, true)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        if (_directoryEntries != null)
          TextButton(
            child: const Text('返回'),
            onPressed: _navigateBack,
          ),
        TextButton(
          child: const Text('关闭'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

// --- 单文件下载测试对话框 (内存) ---
class SimpleFileDownloadDialog extends StatefulWidget {
  const SimpleFileDownloadDialog({Key? key}) : super(key: key);

  @override
  State<SimpleFileDownloadDialog> createState() => _SimpleFileDownloadDialogState();
}

class _SimpleFileDownloadDialogState extends State<SimpleFileDownloadDialog> {
  final TextEditingController _cidController = TextEditingController();
  bool _isLoading = false;
  String? _resultMessage; // 用于显示结果或错误

  @override
  void initState() {
    super.initState();
    _cidController.text = "QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN";
  }

  @override
  void dispose() {
    _cidController.dispose();
    super.dispose();
  }

  Future<void> _downloadIpfsFile() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty) {
      setState(() {
        _resultMessage = "请输入CID。";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      logger.i("尝试通过IPFS下载文件：$cid");
      final fileContent = await LibgopeedBoot.instance.getFileFromIPFS(cid);
      logger.i("成功下载内容，CID: $cid");
      
      setState(() {
        _isLoading = false;
        // 处理Uint8List类型的二进制数据
        String contentPreview;
        if (fileContent.length > 100) {
          // 尝试转换为文本，如果是文本文件
          try {
            contentPreview = utf8.decode(fileContent.sublist(0, 100), allowMalformed: true) + "...";
          } catch (e) {
            // 如果不是有效的UTF-8文本，就显示十六进制
            contentPreview = fileContent.sublist(0, 100).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ') + "...";
          }
        } else {
          try {
            contentPreview = utf8.decode(fileContent, allowMalformed: true);
          } catch (e) {
            contentPreview = fileContent.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
          }
        }
        _resultMessage = "下载成功！\n内容(部分)：$contentPreview";
      });
    } catch (e) {
      logger.e("下载失败，CID: $cid", e);
      setState(() {
        _isLoading = false;
        _resultMessage = "下载失败：\n$e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('单文件下载测试'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _cidController,
              decoration: const InputDecoration(
                labelText: '输入IPFS CID',
                hintText: '例如 QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN',
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_resultMessage != null)
              Text(
                _resultMessage!,
                style: TextStyle(
                    color: _resultMessage!.contains("失败") ? Colors.red : Colors.green),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('取消'),
          onPressed: _isLoading
              ? null
              : () {
                  Navigator.of(context).pop();
                },
        ),
        ElevatedButton(
          child: const Text('下载'),
          onPressed: _isLoading ? null : _downloadIpfsFile,
        ),
      ],
    );
  }
}

// --- 单文件保存测试对话框 ---
class SingleFileSaveDialog extends StatefulWidget {
  const SingleFileSaveDialog({Key? key}) : super(key: key);

  @override
  State<SingleFileSaveDialog> createState() => _SingleFileSaveDialogState();
}

class _SingleFileSaveDialogState extends State<SingleFileSaveDialog> {
  final TextEditingController _cidController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _downloadIdController = TextEditingController();

  bool _isLoading = false;
  String? _statusMessage;
  ProgressInfo? _progressInfo;
  Timer? _timer;
  String _defaultSaveDir = ''; // 用于存储默认路径

  @override
  void initState() {
    super.initState();
    // 设置默认值
    _cidController.text = "QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN"; // 使用单文件 CID
    _downloadIdController.text = "ipfs-save-test-${DateTime.now().millisecondsSinceEpoch}"; // 新的ID前缀
    _loadDefaultSavePath();
  }

  // 获取默认保存路径
  Future<void> _loadDefaultSavePath() async {
    try {
      // 优先使用下载目录，其次临时目录
      Directory? directory = await getDownloadsDirectory();
      directory ??= await getTemporaryDirectory();
      if (directory != null) {
        final String dirPath = directory.path;
        if (mounted) { // 检查 widget 是否挂载
          setState(() {
            _defaultSaveDir = dirPath;
            // 设置默认文件名
            if (_pathController.text.isEmpty) {
               _pathController.text = path.join(dirPath, "ipfs_save_test_file"); // 新的默认文件名
            }
          });
        }
      }
    } catch (e) {
      print("获取默认保存路径失败: $e");
      if (mounted) {
         setState(() {
           _statusMessage = "获取默认保存路径失败: $e";
         });
      }
    }
  }

  @override
  void dispose() {
    _cidController.dispose();
    _pathController.dispose();
    _downloadIdController.dispose();
    _timer?.cancel(); // 停止计时器
    super.dispose();
  }

  // 开始下载
  Future<void> _startDownload() async {
    final cid = _cidController.text.trim();
    final localPath = _pathController.text.trim();
    final downloadID = _downloadIdController.text.trim();

    if (cid.isEmpty || localPath.isEmpty || downloadID.isEmpty) {
      setState(() {
        _statusMessage = "请输入 CID、保存路径和下载 ID。";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "开始下载...";
      _progressInfo = null; // 重置进度
      _timer?.cancel(); // 取消旧的计时器
    });

    try {
      logger.i("调用 downloadAndSaveFile: CID=$cid, Path=$localPath, ID=$downloadID");
      // 调用 Go 函数开始下载 (不直接等待完成)
      await LibgopeedBoot.instance.downloadAndSaveFile(cid, localPath, downloadID);
      logger.i("downloadAndSaveFile 调用成功，开始查询进度: ID=$downloadID");
       if (!mounted) return;
      setState(() {
        _statusMessage = "下载已启动，正在查询进度...";
      });
      // 启动定时器查询进度
      _startProgressTimer(downloadID);
    } catch (e, stacktrace) {
      logger.e("启动下载失败: ID=$downloadID", e, stacktrace);
      if (mounted) {
          setState(() {
            _isLoading = false;
            if (e is PlatformException) {
                _statusMessage = "启动下载失败:\nCode: ${e.code}\nMessage: ${e.message}";
            } else {
               _statusMessage = "启动下载失败:\n${e.toString()}";
            }
            _timer?.cancel();
          });
      }
    }
  }

  // 启动进度查询定时器
  void _startProgressTimer(String downloadID) {
    _timer?.cancel(); // 先取消可能存在的旧计时器
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) { // 检查 Widget 是否还在树中
         timer.cancel();
         return;
      }
      try {
        // 调用 queryDownloadProgress 获取 JSON 字符串
        final String progressJson = await LibgopeedBoot.instance.queryDownloadProgress(downloadID);
        // 解析 JSON
        final Map<String, dynamic> decodedMap = jsonDecode(progressJson);
        // 转换为 ProgressInfo 对象
        final ProgressInfo currentProgress = ProgressInfo.fromJson(decodedMap);

        logger.d("查询进度: ID=$downloadID, Progress: $currentProgress");

        if (!mounted) return; // 再次检查

        setState(() {
          _progressInfo = currentProgress;
          if (currentProgress.isCompleted) {
            _statusMessage = "下载完成！保存在: ${_pathController.text.trim()}";
            _isLoading = false;
            timer.cancel();
          } else if (currentProgress.hasError) {
            _statusMessage = "下载出错: ${currentProgress.errorMessage}";
            _isLoading = false;
            timer.cancel();
          } else {
             _statusMessage = "下载中...";
          }
        });
      } catch (e, stacktrace) {
        // 查询进度失败也需要处理
        logger.w("查询进度失败: ID=$downloadID", e, stacktrace);
        if (mounted) {
           setState(() {
               if (e is PlatformException) {
                  _statusMessage = "查询进度失败:\nCode: ${e.code}\nMessage: ${e.message}";
               } else {
                  _statusMessage = "查询进度失败: ${e.toString()}";
               }
              // 可以在这里添加逻辑：如果连续几次查询失败，则停止计时器
              // 例如：if (consecutiveFailures > 5) timer.cancel();
           });
        } else {
           timer.cancel();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('单文件保存测试'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _cidController,
              decoration: const InputDecoration(
                labelText: 'IPFS 文件 CID',
                hintText: '例如 QmZULk...LFLiXEN',
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pathController,
              decoration: InputDecoration(
                labelText: '本地保存路径 (含文件名)',
                hintText: _defaultSaveDir.isEmpty ? '等待加载默认路径...' : '例如 ${_defaultSaveDir}/ipfs_save_test_file',
              ),
              enabled: !_isLoading,
            ),
             const SizedBox(height: 10),
            TextField(
              controller: _downloadIdController,
              decoration: const InputDecoration(
                labelText: '下载 ID (唯一标识)',
                hintText: '例如 ipfs-save-test-123',
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  if(_progressInfo != null && _progressInfo!.totalBytes > 0)
                    LinearProgressIndicator(
                      // 处理 totalBytes 可能为 -1 (未知大小) 的情况
                      value: (_progressInfo!.totalBytes > 0) 
                             ? _progressInfo!.bytesRetrieved / _progressInfo!.totalBytes 
                             : null, // 大小未知时显示不确定进度条
                      minHeight: 10,
                    ),
                   if(_progressInfo != null)
                     Text( // 显示进度详情
                       // 处理 totalBytes 为 -1 的显示
                       _progressInfo!.totalBytes > 0 
                       ? '${_progressInfo!.bytesRetrieved} / ${_progressInfo!.totalBytes} (${(_progressInfo!.bytesRetrieved * 100 / _progressInfo!.totalBytes).toStringAsFixed(1)}%) - ${_progressInfo!.speedBps.toStringAsFixed(2)} B/s'
                       : '${_progressInfo!.bytesRetrieved} / ??? - ${_progressInfo!.speedBps.toStringAsFixed(2)} B/s',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                ],
              ),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                      color: _statusMessage!.contains("失败") || _statusMessage!.contains("出错") // 调整判断条件
                        ? Colors.red
                        : Colors.green),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('取消'),
          onPressed: _isLoading
              ? null // 下载中不允许取消 (简单处理，也可实现取消逻辑)
              : () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('开始下载'),
          onPressed: _isLoading ? null : _startDownload,
        ),
      ],
    );
  }
}

// --- 新增：获取 IPFS 节点信息对话框 ---
class IpfsInfoDialog extends StatefulWidget {
  const IpfsInfoDialog({Key? key}) : super(key: key);

  @override
  State<IpfsInfoDialog> createState() => _IpfsInfoDialogState();
}

class _IpfsInfoDialogState extends State<IpfsInfoDialog> {
  final TextEditingController _cidController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _nodeInfo;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    // 可以设置一个默认 CID 用于快速测试
    _cidController.text = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"; // 默认用目录 CID
  }

  @override
  void dispose() {
    _cidController.dispose();
    super.dispose();
  }

  Future<void> _getNodeInfo() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty) {
      setState(() { _statusMessage = "请输入 CID。"; });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "正在获取节点信息...";
      _nodeInfo = null; // 清除旧信息
    });

    try {
      logger.i("调用 getIpfsNodeInfo: CID=$cid");
      final String nodeInfoJson = await LibgopeedBoot.instance.getIpfsNodeInfo(cid);
      logger.i("获取到节点信息 JSON: $nodeInfoJson");

      if (!mounted) return;

      final Map<String, dynamic> decodedInfo = jsonDecode(nodeInfoJson);

      setState(() {
        _isLoading = false;
        _nodeInfo = decodedInfo;
        _statusMessage = "获取成功！"; // 清除加载状态
      });

    } catch (e, stacktrace) {
      logger.e("获取节点信息失败: CID=$cid", e, stacktrace);
       if(mounted) setState(() {
        _isLoading = false;
         if (e is PlatformException) {
            _statusMessage = "获取信息失败:\nCode: ${e.code}\nMessage: ${e.message}";
         } else {
           _statusMessage = "获取信息失败:\n${e.toString()}";
         }
      });
    }
  }

  // 用于显示结果的辅助 Widget
  Widget _buildResultDisplay() {
    if (_nodeInfo == null) {
      return Container(); // 没有信息时不显示
    }

    final errorMsg = _nodeInfo!['error'] as String?;
    if (errorMsg != null && errorMsg.isNotEmpty) {
      return Text("错误: $errorMsg", style: const TextStyle(color: Colors.red));
    }

    final nodeType = _nodeInfo!['type'] as String? ?? 'unknown';
    final List<Widget> infoWidgets = [Text("类型: $nodeType")];

    if (nodeType == 'file') {
      final fileSize = _nodeInfo!['size'] as int? ?? -1;
      infoWidgets.add(Text("大小: ${fileSize >= 0 ? fileSize.toString() : '未知'}"));
      // 可以添加一个按钮来触发 downloadAndSaveFile
      infoWidgets.add(Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: ElevatedButton(onPressed: (){ /* TODO: 触发下载 */ }, child: Text("下载此文件")),
      ));
    } else if (nodeType == 'directory') {
      final List<dynamic> entriesList = _nodeInfo!['entries'] ?? [];
      infoWidgets.add(Text("条目数: ${entriesList.length}"));
      if (entriesList.isNotEmpty) {
         infoWidgets.add(const Text("部分条目:"));
         infoWidgets.addAll(entriesList.take(5).map((item) {
            final entry = DirectoryEntry.fromJson(item as Map<String, dynamic>);
            return Text("  - ${entry.name} (${entry.type})");
         }));
         if (entriesList.length > 5) {
            infoWidgets.add(const Text("  ..."));
         }
      }
       // 可以添加一个按钮来触发 startDownloadSelected
      infoWidgets.add(Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: ElevatedButton(onPressed: (){ /* TODO: 触发选择性下载 */}, child: Text("下载此目录 (全部)")), // 简化：先做下载全部
      ));
    } else {
      infoWidgets.add(const Text("未知节点类型或无法解析信息。"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: infoWidgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('获取 IPFS 节点信息'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _cidController,
              decoration: const InputDecoration(
                labelText: 'IPFS CID',
                hintText: '输入文件或目录 CID',
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_statusMessage != null && _nodeInfo == null) // 显示获取前的状态或错误
              Text(
                 _statusMessage!,
                  style: TextStyle(
                      color: _statusMessage!.contains("失败") 
                          ? Colors.red
                          : Colors.grey), // 非成功状态用灰色
               )
            else if (_nodeInfo != null)
              _buildResultDisplay(), // 显示解析后的节点信息
              
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('关闭'),
          onPressed: _isLoading ? null : () {
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('获取信息'),
          onPressed: _isLoading ? null : _getNodeInfo,
        ),
      ],
    );
  }
}
