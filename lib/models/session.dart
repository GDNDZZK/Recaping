import 'dart:convert';
import 'dart:typed_data';

/// 会话模型
///
/// 代表一次完整的录音会话，包含会话元信息、音频配置、统计信息等。
/// 每个会话对应一个 `.recp` 文件（SQLite 数据库）。
/// Author: GDNDZZK
class Session {
  /// 会话唯一标识（UUID）
  final String sessionId;

  /// 会话标题
  final String title;

  /// 会话描述
  final String? description;

  /// 创建时间
  final DateTime createdAt;

  /// 最后更新时间
  final DateTime updatedAt;

  /// 总时间轴时长（毫秒）
  final int duration;

  /// 实际录音时长（毫秒）
  final int audioDuration;

  /// 音频格式（如 aac）
  final String audioFormat;

  /// 音频采样率
  final int audioSampleRate;

  /// 音频声道数
  final int audioChannels;

  /// 事件总数（照片 + 视频 + 笔记 + 书签）
  final int eventCount;

  /// 标签列表
  final List<String> tags;

  /// 纬度（可选）
  final double? locationLat;

  /// 经度（可选）
  final double? locationLng;

  /// 设备信息（可选）
  final String? deviceInfo;

  /// 缩略图数据（可选）
  final Uint8List? thumbnail;

  const Session({
    required this.sessionId,
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.duration = 0,
    this.audioDuration = 0,
    this.audioFormat = 'aac',
    this.audioSampleRate = 44100,
    this.audioChannels = 1,
    this.eventCount = 0,
    this.tags = const [],
    this.locationLat,
    this.locationLng,
    this.deviceInfo,
    this.thumbnail,
  });

  /// 从数据库 Map 创建 Session 实例
  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      sessionId: map['session_id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      duration: map['duration'] as int? ?? 0,
      audioDuration: map['audio_duration'] as int? ?? 0,
      audioFormat: map['audio_format'] as String? ?? 'aac',
      audioSampleRate: map['audio_sample_rate'] as int? ?? 44100,
      audioChannels: map['audio_channels'] as int? ?? 1,
      eventCount: map['event_count'] as int? ?? 0,
      tags: _parseTags(map['tags'] as String?),
      locationLat: map['location_lat'] as double?,
      locationLng: map['location_lng'] as double?,
      deviceInfo: map['device_info'] as String?,
      thumbnail: map['thumbnail'] as Uint8List?,
    );
  }

  /// 从 info 表的 key-value 对创建 Session 实例
  factory Session.fromInfoMap(Map<String, String> info) {
    return Session(
      sessionId: info['session_id'] ?? '',
      title: info['title'] ?? '',
      description: info['description'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(info['created_at'] ?? '0') ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(info['updated_at'] ?? '0') ?? 0,
      ),
      duration: int.tryParse(info['duration'] ?? '0') ?? 0,
      audioDuration: int.tryParse(info['audio_duration'] ?? '0') ?? 0,
      audioFormat: info['audio_format'] ?? 'aac',
      audioSampleRate:
          int.tryParse(info['audio_sample_rate'] ?? '44100') ?? 44100,
      audioChannels:
          int.tryParse(info['audio_channels'] ?? '1') ?? 1,
      eventCount: int.tryParse(info['event_count'] ?? '0') ?? 0,
      tags: _parseTags(info['tags']),
      locationLat:
          info['location_lat'] != null
              ? double.tryParse(info['location_lat']!)
              : null,
      locationLng:
          info['location_lng'] != null
              ? double.tryParse(info['location_lng']!)
              : null,
      deviceInfo: info['device_info'],
      thumbnail: null, // 缩略图需要单独从 BLOB 字段获取
    );
  }

  /// 转换为数据库 Map（用于 session_summaries 表）
  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'title': title,
      'description': description,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'duration': duration,
      'audio_duration': audioDuration,
      'audio_format': audioFormat,
      'audio_sample_rate': audioSampleRate,
      'audio_channels': audioChannels,
      'event_count': eventCount,
      'tags': jsonEncode(tags),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'device_info': deviceInfo,
      'thumbnail': thumbnail,
    };
  }

  /// 转换为 info 表的 key-value 对（用于 .recp 文件中的 info 表）
  Map<String, String> toInfoMap() {
    final map = <String, String>{
      'session_id': sessionId,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch.toString(),
      'updated_at': updatedAt.millisecondsSinceEpoch.toString(),
      'duration': duration.toString(),
      'audio_duration': audioDuration.toString(),
      'audio_format': audioFormat,
      'audio_sample_rate': audioSampleRate.toString(),
      'audio_channels': audioChannels.toString(),
      'event_count': eventCount.toString(),
      'tags': jsonEncode(tags),
    };
    if (description != null) map['description'] = description!;
    if (locationLat != null) map['location_lat'] = locationLat.toString();
    if (locationLng != null) map['location_lng'] = locationLng.toString();
    if (deviceInfo != null) map['device_info'] = deviceInfo!;
    return map;
  }

  /// 复制并修改部分字段
  Session copyWith({
    String? sessionId,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? duration,
    int? audioDuration,
    String? audioFormat,
    int? audioSampleRate,
    int? audioChannels,
    int? eventCount,
    List<String>? tags,
    double? locationLat,
    double? locationLng,
    String? deviceInfo,
    Uint8List? thumbnail,
  }) {
    return Session(
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      duration: duration ?? this.duration,
      audioDuration: audioDuration ?? this.audioDuration,
      audioFormat: audioFormat ?? this.audioFormat,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      eventCount: eventCount ?? this.eventCount,
      tags: tags ?? this.tags,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }

  @override
  String toString() {
    return 'Session('
        'sessionId: $sessionId, '
        'title: $title, '
        'duration: $duration, '
        'audioDuration: $audioDuration, '
        'eventCount: $eventCount'
        ')';
  }

  /// 解析标签 JSON 字符串
  static List<String> _parseTags(String? tagsJson) {
    if (tagsJson == null || tagsJson.isEmpty) return [];
    try {
      final list = jsonDecode(tagsJson) as List;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }
}
