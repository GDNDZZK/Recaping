/// 音频分片模型
///
/// 代表录音过程中的一段音频数据，默认每 15 秒为一个分片。
/// 音频数据存储在文件系统中，数据库只保存文件路径引用。
/// Author: GDNDZZK
class AudioChunk {
  /// 分片唯一标识（UUID）
  final String id;

  /// 分片序号（从 0 开始）
  final int chunkIndex;

  /// 开始时间（相对于录音时间轴的毫秒偏移）
  final int startTime;

  /// 结束时间（相对于录音时间轴的毫秒偏移）
  final int endTime;

  /// 在总时间轴上的开始时间（毫秒）
  ///
  /// 记录该分片在总时间轴（包含静音间隔）上的起始位置。
  /// 旧数据可能为 0，此时回放服务会退回到使用 [startTime]。
  final int totalStartTime;

  /// 在总时间轴上的结束时间（毫秒）
  ///
  /// 记录该分片在总时间轴上的终止位置。
  /// 旧数据可能为 0，此时回放服务会退回到使用 [endTime]。
  final int totalEndTime;

  /// 音频文件相对路径（相对于会话目录，如 audio/chunk_0.aac）
  final String filePath;

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
    required this.filePath,
    this.totalStartTime = 0,
    this.totalEndTime = 0,
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
      filePath: map['file_path'] as String,
      totalStartTime: (map['total_start_time'] as int?) ?? 0,
      totalEndTime: (map['total_end_time'] as int?) ?? 0,
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
      'total_start_time': totalStartTime,
      'total_end_time': totalEndTime,
      'file_path': filePath,
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
    int? totalStartTime,
    int? totalEndTime,
    String? filePath,
    String? format,
    int? sampleRate,
    int? channels,
  }) {
    return AudioChunk(
      id: id ?? this.id,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalStartTime: totalStartTime ?? this.totalStartTime,
      totalEndTime: totalEndTime ?? this.totalEndTime,
      filePath: filePath ?? this.filePath,
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
        'totalStartTime: $totalStartTime, '
        'totalEndTime: $totalEndTime, '
        'filePath: $filePath, '
        'format: $format'
        ')';
  }
}
