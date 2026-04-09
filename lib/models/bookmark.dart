/// 书签模型
///
/// 代表录音时间轴上的一个标记点，用于快速定位和导航。
/// Author: GDNDZZK
class Bookmark {
  /// 书签唯一标识（UUID）
  final String id;

  /// 时间戳（相对于会话开始的毫秒偏移）
  final int timestamp;

  /// 书签标签（可选）
  final String? label;

  /// 书签颜色（十六进制颜色值，如 #FF6B6B）
  final String color;

  /// 创建时间
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.timestamp,
    this.label,
    this.color = '#FF6B6B',
    required this.createdAt,
  });

  /// 从数据库 Map 创建 Bookmark 实例
  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'] as String,
      timestamp: map['timestamp'] as int,
      label: map['label'] as String?,
      color: map['color'] as String? ?? '#FF6B6B',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'label': label,
      'color': color,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改部分字段
  Bookmark copyWith({
    String? id,
    int? timestamp,
    String? label,
    String? color,
    DateTime? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      label: label ?? this.label,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Bookmark('
        'id: $id, '
        'timestamp: $timestamp, '
        'label: $label, '
        'color: $color'
        ')';
  }
}
