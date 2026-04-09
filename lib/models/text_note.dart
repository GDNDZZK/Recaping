/// 文字笔记模型
///
/// 代表录音过程中添加的文字笔记，关联到录音时间轴上的某个时间点。
/// Author: GDNDZZK
class TextNote {
  /// 笔记唯一标识（UUID）
  final String id;

  /// 时间戳（相对于会话开始的毫秒偏移）
  final int timestamp;

  /// 笔记标题（可选）
  final String? title;

  /// 笔记内容
  final String content;

  /// 创建时间
  final DateTime createdAt;

  const TextNote({
    required this.id,
    required this.timestamp,
    this.title,
    required this.content,
    required this.createdAt,
  });

  /// 从数据库 Map 创建 TextNote 实例
  factory TextNote.fromMap(Map<String, dynamic> map) {
    return TextNote(
      id: map['id'] as String,
      timestamp: map['timestamp'] as int,
      title: map['title'] as String?,
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'title': title,
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改部分字段
  TextNote copyWith({
    String? id,
    int? timestamp,
    String? title,
    String? content,
    DateTime? createdAt,
  }) {
    return TextNote(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'TextNote('
        'id: $id, '
        'timestamp: $timestamp, '
        'title: $title, '
        'content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content}'
        ')';
  }
}
