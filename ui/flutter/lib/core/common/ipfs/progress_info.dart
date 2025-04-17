// progress_info.dart
import 'dart:typed_data'; // 如果需要 Uint8List

class ProgressInfo {
  final int totalBytes;
  final int bytesRetrieved;
  final double speedBps;
  final double elapsedTimeSec;
  final bool isCompleted;
  final bool hasError;
  final String errorMessage;

  ProgressInfo({
    required this.totalBytes,
    required this.bytesRetrieved,
    required this.speedBps,
    required this.elapsedTimeSec,
    required this.isCompleted,
    required this.hasError,
    required this.errorMessage,
  });

  factory ProgressInfo.fromJson(Map<String, dynamic> json) {
    return ProgressInfo(
      totalBytes: json['totalBytes'] ?? -1,
      bytesRetrieved: json['bytesRetrieved'] ?? 0,
      speedBps: (json['speedBps'] ?? 0.0).toDouble(),
      elapsedTimeSec: (json['elapsedTimeSec'] ?? 0.0).toDouble(),
      isCompleted: json['isCompleted'] ?? false,
      hasError: json['hasError'] ?? false,
      errorMessage: json['errorMessage'] ?? '',
    );
  }
  // 可能需要 toJson
  Map<String, dynamic> toJson() => {
        'totalBytes': totalBytes,
        'bytesRetrieved': bytesRetrieved,
        'speedBps': speedBps,
        'elapsedTimeSec': elapsedTimeSec,
        'isCompleted': isCompleted,
        'hasError': hasError,
        'errorMessage': errorMessage,
      };
}
