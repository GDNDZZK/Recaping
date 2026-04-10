/// 视频分片模型
///
/// 代表录音过程中录制的短视频片段，默认每 5 秒为一个分片。
/// 视频数据和缩略图存储在文件系统中，数据库只保存文件路径引用。
/// Author: GDNDZZK
class VideoChunk {
  /// 分片唯一标识（UUID）
  final String id;

  /// 视频流标识（同一次视频录制可能产生多个分片）
  final String videoId;

  /// 分片序号（从 0 开始）
  final int chunkIndex;

  /// 开始时间（相对于会话开始的毫秒偏移）
  final int startTime;

  /// 结束时间（相对于会话开始的毫秒偏移）
  final int endTime;

  /// 视频文件相对路径（相对于会话目录）
  final String filePath;

  /// 视频格式（如 mp4）
  final String format;

  /// 缩略图文件相对路径（相对于会话目录，可选）
  final String? thumbnailPath;

  const VideoChunk({
    required this.id,
    required this.videoId,
    required this.chunkIndex,
    required this.startTime,
    required this.endTime,
    required this.filePath,
    this.format = 'mp4',
    this.thumbnailPath,
  });

  /// 从数据库 Map 创建 VideoChunk 实例
  factory VideoChunk.fromMap(Map<String, dynamic> map) {
    return VideoChunk(
      id: map['id'] as String,
      videoId: map['video_id'] as String,
      chunkIndex: map['chunk_index'] as int,
      startTime: map['start_time'] as int,
      endTime: map['end_time'] as int,
      filePath: map['file_path'] as String,
      format: map['format'] as String? ?? 'mp4',
      thumbnailPath: map['thumbnail_path'] as String?,
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'video_id': videoId,
      'chunk_index': chunkIndex,
      'start_time': startTime,
      'end_time': endTime,
      'file_path': filePath,
      'format': format,
      'thumbnail_path': thumbnailPath,
    };
  }

  /// 复制并修改部分字段
  VideoChunk copyWith({
    String? id,
    String? videoId,
    int? chunkIndex,
    int? startTime,
    int? endTime,
    String? filePath,
    String? format,
    String? thumbnailPath,
  }) {
    return VideoChunk(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  /// 分片时长（毫秒）
  int get duration => endTime - startTime;

  @override
  String toString() {
    return 'VideoChunk('
        'id: $id, '
        'videoId: $videoId, '
        'chunkIndex: $chunkIndex, '
        'startTime: $startTime, '
        'endTime: $endTime, '
        'filePath: $filePath, '
        'format: $format'
        ')';
  }
}
