import 'dart:typed_data';

/// 时间轴事件类型枚举
///
/// 定义时间轴上可以展示的事件类型。
/// Author: GDNDZZK
enum TimelineEventType {
  /// 照片
  photo,

  /// 视频片段
  video,

  /// 文字笔记
  textNote,

  /// 书签
  bookmark,
}

/// 时间轴事件模型
///
/// 用于 UI 展示的统一时间轴事件，聚合了照片、视频、笔记和书签数据。
/// 通过 [type] 字段区分不同类型的事件。
/// Author: GDNDZZK
class TimelineEvent {
  /// 事件唯一标识
  final String id;

  /// 事件类型
  final TimelineEventType type;

  /// 时间戳（相对于会话开始的毫秒偏移）
  final int timestamp;

  /// 标签文本（书签标签、笔记标题等）
  final String? label;

  /// 颜色（书签颜色等）
  final String? color;

  /// 文本内容（笔记内容等）
  final String? textContent;

  /// 缩略图数据（照片/视频缩略图）
  final Uint8List? thumbnail;

  const TimelineEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.label,
    this.color,
    this.textContent,
    this.thumbnail,
  });

  /// 从照片数据创建时间轴事件
  factory TimelineEvent.fromPhoto({
    required String id,
    required int timestamp,
    Uint8List? thumbnail,
  }) {
    return TimelineEvent(
      id: id,
      type: TimelineEventType.photo,
      timestamp: timestamp,
      thumbnail: thumbnail,
    );
  }

  /// 从视频数据创建时间轴事件
  factory TimelineEvent.fromVideo({
    required String id,
    required int timestamp,
    Uint8List? thumbnail,
  }) {
    return TimelineEvent(
      id: id,
      type: TimelineEventType.video,
      timestamp: timestamp,
      thumbnail: thumbnail,
    );
  }

  /// 从文字笔记创建时间轴事件
  factory TimelineEvent.fromTextNote({
    required String id,
    required int timestamp,
    String? title,
    required String content,
  }) {
    return TimelineEvent(
      id: id,
      type: TimelineEventType.textNote,
      timestamp: timestamp,
      label: title,
      textContent: content,
    );
  }

  /// 从书签创建时间轴事件
  factory TimelineEvent.fromBookmark({
    required String id,
    required int timestamp,
    String? label,
    String color = '#FF6B6B',
  }) {
    return TimelineEvent(
      id: id,
      type: TimelineEventType.bookmark,
      timestamp: timestamp,
      label: label,
      color: color,
    );
  }

  /// 复制并修改部分字段
  TimelineEvent copyWith({
    String? id,
    TimelineEventType? type,
    int? timestamp,
    String? label,
    String? color,
    String? textContent,
    Uint8List? thumbnail,
  }) {
    return TimelineEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      label: label ?? this.label,
      color: color ?? this.color,
      textContent: textContent ?? this.textContent,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }

  @override
  String toString() {
    return 'TimelineEvent('
        'id: $id, '
        'type: $type, '
        'timestamp: $timestamp, '
        'label: $label'
        ')';
  }
}
