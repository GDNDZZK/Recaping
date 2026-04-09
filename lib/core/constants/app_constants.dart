/// 应用常量定义
///
/// 包含应用名称、版本号、音频/视频/图片配置、数据库配置等常量
/// Author: GDNDZZK
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'Recaping';

  /// 文件格式魔数标识
  static const String magicIdentifier = 'RECAPING_SESSION';

  /// 文件格式版本号
  static const int formatVersion = 1;

  /// 应用版本号
  static const String appVersion = '0.1.0';

  // ==================== 音频配置 ====================

  /// 默认音频格式
  static const String defaultAudioFormat = 'aac';

  /// 默认采样率
  static const int defaultSampleRate = 44100;

  /// 默认声道数
  static const int defaultChannels = 1;

  /// 音频分片时长（毫秒），15秒分段
  static const int audioChunkDurationMs = 15000;

  // ==================== 视频配置 ====================

  /// 默认视频格式
  static const String defaultVideoFormat = 'mp4';

  /// 视频分片时长（毫秒），5秒分段
  static const int videoChunkDurationMs = 5000;

  // ==================== 图片配置 ====================

  /// 默认照片格式
  static const String defaultPhotoFormat = 'jpeg';

  /// 缩略图最大尺寸（像素）
  static const int thumbnailMaxSize = 200;

  // ==================== 书签配置 ====================

  /// 默认书签颜色
  static const String defaultBookmarkColor = '#FF6B6B';

  // ==================== 数据库配置 ====================

  /// 全局配置数据库名称
  static const String configDbName = 'app_config.db';

  /// sessions 目录名
  static const String sessionsDir = 'sessions';

  /// 临时文件目录名
  static const String tempDir = 'temp';

  /// 会话文件扩展名
  static const String recpFileExtension = '.recp';
}
