/// 照片模型
///
/// 代表录音过程中拍摄的照片。
/// 照片数据和缩略图存储在文件系统中，数据库只保存文件路径引用。
/// Author: GDNDZZK
class Photo {
  /// 照片唯一标识（UUID）
  final String id;

  /// 拍摄时间（相对于会话开始的毫秒偏移）
  final int timestamp;

  /// 照片文件相对路径（相对于会话目录，如 photos/{id}.jpeg）
  final String filePath;

  /// 缩略图文件相对路径（相对于会话目录，如 thumbnails/{id}_thumb.jpeg）
  final String thumbnailPath;

  /// 图片格式（如 jpeg）
  final String format;

  /// 图片宽度（像素）
  final int width;

  /// 图片高度（像素）
  final int height;

  const Photo({
    required this.id,
    required this.timestamp,
    required this.filePath,
    required this.thumbnailPath,
    this.format = 'jpeg',
    this.width = 0,
    this.height = 0,
  });

  /// 从数据库 Map 创建 Photo 实例
  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      id: map['id'] as String,
      timestamp: map['timestamp'] as int,
      filePath: map['file_path'] as String,
      thumbnailPath: map['thumbnail_path'] as String,
      format: map['format'] as String? ?? 'jpeg',
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'file_path': filePath,
      'thumbnail_path': thumbnailPath,
      'format': format,
      'width': width,
      'height': height,
    };
  }

  /// 复制并修改部分字段
  Photo copyWith({
    String? id,
    int? timestamp,
    String? filePath,
    String? thumbnailPath,
    String? format,
    int? width,
    int? height,
  }) {
    return Photo(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      format: format ?? this.format,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  String toString() {
    return 'Photo('
        'id: $id, '
        'timestamp: $timestamp, '
        'filePath: $filePath, '
        'format: $format, '
        'width: $width, '
        'height: $height'
        ')';
  }
}
