// directory_entry.dart
class DirectoryEntry {
  final String name;
  final String cid;
  final String type; // "file" or "directory"
  final int size; // Dart int 可以表示 Go int64

  DirectoryEntry({
    required this.name,
    required this.cid,
    required this.type,
    required this.size,
  });

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) {
    return DirectoryEntry(
      name: json['name'] ?? '',
      cid: json['cid'] ?? '',
      type: json['type'] ?? 'unknown',
      size: json['size'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        // 可能需要 toJson 用于其他地方
        'name': name,
        'cid': cid,
        'type': type,
        'size': size,
      };
}
