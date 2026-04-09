import 'dart:typed_data';

/// 音频分片模型
///
/// 代表录音过程中的一段音频数据，默认每 15 秒为一个分片。
/// 音频数据以 BLOB 形式直接存储在数据库中。
/// Author: GDNDZZK
class AudioChunk {
  /// 分片唯一标识（UUID）
  final String id;

  /// 分片序号（从 0 开始）
  final int chunkIndex;

  /// 开始时间（相对于会话开始的毫秒偏移）
  final int startTime;

  /// 结束时间（相对于会话开始的毫秒偏移）
  final int endTime;

  /// 音频数据
  final Uint8List data;

  /// 音频格式（如 aac）
  final String format;

  /// 采样率
  final int sampleRate;

  /// 声道数
  final int channels;

  const AudioChunk({
    required this.id,
    required this.chunkIndex,
    required this.startTime,
    required this.endTime,
    required this.data,
    this.format = 'aac',
    this.sampleRate = 44100,
    this.channels = 1,
  });

  /// 从数据库 Map 创建 AudioChunk 实例
  factory AudioChunk.fromMap(Map<String, dynamic> map) {
    return AudioChunk(
      id: map['id'] as String,
      chunkIndex: map['chunk_index'] as int,
      startTime: map['start_time'] as int,
      endTime: map['end_time'] as int,
      data: map['data'] as Uint8List,
      format: map['format'] as String? ?? 'aac',
      sampleRate: map['sample_rate'] as int? ?? 44100,
      channels: map['channels'] as int? ?? 1,
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chunk_index': chunkIndex,
      'start_time': startTime,
      'end_time': endTime,
      'data': data,
      'format': format,
      'sample_rate': sampleRate,
      'channels': channels,
    };
  }

  /// 复制并修改部分字段
  AudioChunk copyWith({
    String? id,
    int? chunkIndex,
    int? startTime,
    int? endTime,
    Uint8List? data,
    String? format,
    int? sampleRate,
    int? channels,
  }) {
    return AudioChunk(
      id: id ?? this.id,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      data: data ?? this.data,
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
    );
  }

  /// 分片时长（毫秒）
  int get duration => endTime - startTime;

  @override
  String toString() {
    return 'AudioChunk('
        'id: $id, '
        'chunkIndex: $chunkIndex, '
        'startTime: $startTime, '
        'endTime: $endTime, '
        'format: $format'
        ')';
  }
}
