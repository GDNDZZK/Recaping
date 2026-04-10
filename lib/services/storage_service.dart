import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/database/config_database.dart';
import '../core/database/database_helper.dart';
import '../core/database/session_database.dart';
import '../core/utils/thumbnail_util.dart';
import '../models/session.dart';

/// 存储空间统计信息
class StorageStats {
  /// 会话总数
  final int totalSessions;

  /// 总占用空间（字节）
  final int totalSizeBytes;

  /// 音频数据占用空间（字节）
  final int audioSizeBytes;

  /// 照片数据占用空间（字节）
  final int photosSizeBytes;

  /// 视频数据占用空间（字节）
  final int videosSizeBytes;

  const StorageStats({
    this.totalSessions = 0,
    this.totalSizeBytes = 0,
    this.audioSizeBytes = 0,
    this.photosSizeBytes = 0,
    this.videosSizeBytes = 0,
  });

  @override
  String toString() =>
      'StorageStats('
      'totalSessions: $totalSessions, '
      'totalSizeBytes: $totalSizeBytes, '
      'audioSizeBytes: $audioSizeBytes, '
      'photosSizeBytes: $photosSizeBytes, '
      'videosSizeBytes: $videosSizeBytes'
      ')';
}

/// 存储管理服务
///
/// 管理会话的创建、删除、列表等操作。
/// 负责协调 [DatabaseHelper]、[ConfigDatabase] 和 [SessionDatabase] 之间的交互。
/// Author: GDNDZZK
class StorageService {
  final DatabaseHelper _dbHelper;
  final ConfigDatabase _configDb;
  final _uuid = const Uuid();

  /// 已打开的 SessionDatabase 缓存
  final Map<String, SessionDatabase> _openDatabases = {};

  StorageService(this._dbHelper, this._configDb);

  // ==================== 会话管理 ====================

  /// 创建新会话
  ///
  /// [title] 会话标题（可选，默认使用日期时间格式）
  ///
  /// 创建会话目录结构（audio/photos/videos/thumbnails）和 session.db，
  /// 同时在全局配置数据库中保存摘要。
  Future<Session> createSession({String? title}) async {
    final sessionId = _uuid.v4();
    final now = DateTime.now();

    // 使用默认标题（如果未提供）
    final sessionTitle = title ??
        '录音 ${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)} '
        '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}';

    // 创建 Session 对象
    final session = Session(
      sessionId: sessionId,
      title: sessionTitle,
      createdAt: now,
      updatedAt: now,
      audioFormat: AppConstants.defaultAudioFormat,
      audioSampleRate: AppConstants.defaultSampleRate,
      audioChannels: AppConstants.defaultChannels,
    );

    // 确保会话目录结构存在（openSession 内部会调用 ensureSessionDirs）
    final sessionDb = await openSession(sessionId);

    // 保存会话元信息到 session.db 的 info 表
    await sessionDb.saveSessionInfo(session);

    // 保存会话摘要到全局配置数据库
    await _configDb.saveSessionSummary(session);

    return session;
  }

  /// 获取所有会话列表
  ///
  /// 从全局配置数据库的 session_summaries 表获取，按更新时间降序排列。
  Future<List<Session>> getAllSessions() async {
    return _configDb.getSessionSummaries();
  }

  /// 获取会话详情
  ///
  /// 优先从全局摘要获取基本信息，然后从 session.db 获取完整信息。
  Future<Session?> getSession(String sessionId) async {
    // 先尝试从 session.db 获取完整信息
    try {
      final sessionDb = await openSession(sessionId);
      final session = await sessionDb.getSessionInfo();
      if (session != null) return session;
    } catch (_) {
      // 如果 session.db 打开失败，回退到摘要
    }

    // 回退到全局摘要
    final summaries = await _configDb.getSessionSummaries();
    try {
      return summaries.firstWhere((s) => s.sessionId == sessionId);
    } catch (_) {
      return null;
    }
  }

  /// 更新会话信息
  ///
  /// 同时更新 session.db 和全局摘要。
  Future<void> updateSession(Session session) async {
    final updatedSession = session.copyWith(
      updatedAt: DateTime.now(),
    );

    // 更新 session.db
    final sessionDb = await openSession(session.sessionId);
    await sessionDb.saveSessionInfo(updatedSession);

    // 更新全局摘要
    await _configDb.updateSessionSummary(updatedSession);
  }

  /// 删除会话
  ///
  /// 删除整个会话目录（包含 session.db 和所有媒体文件）以及全局摘要记录。
  Future<void> deleteSession(String sessionId) async {
    // 关闭并移除缓存
    await _closeSessionDatabase(sessionId);

    // 删除整个会话目录
    await _dbHelper.deleteSessionDirectory(sessionId);

    // 删除全局摘要
    await _configDb.deleteSessionSummary(sessionId);
  }

  /// 搜索会话
  ///
  /// [query] 搜索关键词，匹配标题和描述
  Future<List<Session>> searchSessions(String query) async {
    final allSessions = await getAllSessions();
    final lowerQuery = query.toLowerCase();
    return allSessions.where((session) {
      final titleMatch = session.title.toLowerCase().contains(lowerQuery);
      final descMatch = session.description?.toLowerCase().contains(lowerQuery) ??
          false;
      return titleMatch || descMatch;
    }).toList();
  }

  // ==================== 数据库连接管理 ====================

  /// 打开会话数据库
  ///
  /// 使用缓存机制，避免重复打开同一会话的数据库。
  Future<SessionDatabase> openSession(String sessionId) async {
    if (_openDatabases.containsKey(sessionId)) {
      return _openDatabases[sessionId]!;
    }

    final sessionDb = await SessionDatabase.create(sessionId);
    _openDatabases[sessionId] = sessionDb;
    return sessionDb;
  }

  /// 关闭会话数据库
  Future<void> closeSession(String sessionId) async {
    await _closeSessionDatabase(sessionId);
  }

  // ==================== 存储统计 ====================

  /// 获取存储空间统计
  ///
  /// 遍历所有会话目录计算总大小。
  Future<StorageStats> getStorageStats() async {
    final sessionsDir = await _dbHelper.sessionsPath;
    final dir = Directory(sessionsDir);

    int totalSize = 0;
    int sessionCount = 0;

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          // 每个子目录代表一个会话
          sessionCount++;
          totalSize += await _calculateDirectorySize(entity);
        }
      }
    }

    return StorageStats(
      totalSessions: sessionCount,
      totalSizeBytes: totalSize,
    );
  }

  // ==================== 清理功能 ====================

  /// 清理临时文件
  ///
  /// 清除 temp 目录下的所有文件，返回被删除的文件数量。
  /// Author: GDNDZZK
  Future<int> clearTempFiles() async {
    final tempPath = await _dbHelper.tempPath;
    final tempDir = Directory(tempPath);
    if (!await tempDir.exists()) return 0;

    int deletedCount = 0;
    await for (final entity in tempDir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
          deletedCount++;
        } catch (_) {
          // 忽略删除失败的文件
        }
      }
    }
    return deletedCount;
  }

  /// 清理指定天数之前的旧会话
  ///
  /// [olderThanDays] 超过多少天未更新的会话将被删除，默认 90 天
  /// 返回被删除的会话 ID 列表。
  /// Author: GDNDZZK
  Future<List<String>> cleanOldSessions({int olderThanDays = 90}) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    final sessions = await getAllSessions();
    final oldSessions = sessions
        .where((s) => s.updatedAt.isBefore(cutoff))
        .toList();

    final deletedIds = <String>[];
    for (final session in oldSessions) {
      await deleteSession(session.sessionId);
      deletedIds.add(session.sessionId);
    }
    return deletedIds;
  }

  /// 压缩会话中的媒体文件（重新生成更小的缩略图）
  ///
  /// [sessionId] 会话 ID
  /// [thumbnailMaxSize] 新缩略图的最大边长（像素），默认 100
  /// 返回节省的空间（字节）。
  /// Author: GDNDZZK
  Future<int> compressSessionMedia(
    String sessionId, {
    int thumbnailMaxSize = 100,
  }) async {
    final sessionDb = await openSession(sessionId);
    final photos = await sessionDb.getPhotos();
    int savedBytes = 0;

    for (final photo in photos) {
      // 读取原图文件
      final photoAbsPath = await sessionDb.resolvePath(photo.filePath);
      final photoFile = File(photoAbsPath);
      if (!await photoFile.exists()) continue;

      final imageData = await photoFile.readAsBytes();

      // 读取旧缩略图大小
      final thumbAbsPath = await sessionDb.resolvePath(photo.thumbnailPath);
      final thumbFile = File(thumbAbsPath);
      final oldThumbnailSize = await thumbFile.exists() ? await thumbFile.length() : 0;

      // 使用原图重新生成更小的缩略图
      final newThumbnail = await ThumbnailUtil.generate(
        imageData,
        maxSize: thumbnailMaxSize,
      );

      // 计算节省的空间
      if (newThumbnail.length < oldThumbnailSize) {
        savedBytes += oldThumbnailSize - newThumbnail.length;

        // 更新缩略图文件
        await thumbFile.writeAsBytes(newThumbnail);
      }
    }

    return savedBytes;
  }

  /// 获取所有会话的详细存储统计
  ///
  /// 遍历每个会话目录，统计音频、照片、视频的占用空间。
  /// Author: GDNDZZK
  Future<StorageStats> getDetailedStorageStats() async {
    final sessions = await getAllSessions();
    int totalSize = 0;
    int audioSize = 0;
    int photosSize = 0;
    int videosSize = 0;

    for (final session in sessions) {
      try {
        final sessionDir = await _dbHelper.sessionDirPath(session.sessionId);
        final dir = Directory(sessionDir);
        if (!await dir.exists()) continue;

        // 统计各子目录大小
        final audioDir = Directory(p.join(sessionDir, 'audio'));
        final photosDir = Directory(p.join(sessionDir, 'photos'));
        final videosDir = Directory(p.join(sessionDir, 'videos'));

        if (await audioDir.exists()) {
          audioSize += await _calculateDirectorySize(audioDir);
        }
        if (await photosDir.exists()) {
          photosSize += await _calculateDirectorySize(photosDir);
        }
        if (await videosDir.exists()) {
          videosSize += await _calculateDirectorySize(videosDir);
        }

        // 加上整个会话目录的大小（包含数据库和其他文件）
        totalSize += await _calculateDirectorySize(dir);
      } catch (_) {
        // 忽略打开失败的会话
      }
    }

    return StorageStats(
      totalSessions: sessions.length,
      totalSizeBytes: totalSize,
      audioSizeBytes: audioSize,
      photosSizeBytes: photosSize,
      videosSizeBytes: videosSize,
    );
  }

  // ==================== 私有方法 ====================

  /// 关闭并移除缓存的 SessionDatabase
  Future<void> _closeSessionDatabase(String sessionId) async {
    final sessionDb = _openDatabases.remove(sessionId);
    // SessionDatabase 本身不持有需要关闭的资源，
    // 底层 Database 由 DatabaseHelper 管理
    if (sessionDb != null) {
      await _dbHelper.closeSessionDatabase(sessionId);
    }
  }

  /// 递归计算目录大小
  Future<int> _calculateDirectorySize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (_) {
      // 忽略无法访问的文件
    }
    return size;
  }

  /// 格式化两位数字
  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
