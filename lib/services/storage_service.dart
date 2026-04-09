import 'dart:io';

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
  /// 创建 .recp 文件并初始化会话元信息，同时在全局配置数据库中保存摘要。
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

    // 打开会话数据库（自动创建 .recp 文件）
    final sessionDb = await openSession(sessionId);

    // 保存会话元信息到 .recp 文件的 info 表
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
  /// 优先从全局摘要获取基本信息，然后从 .recp 文件获取完整信息。
  Future<Session?> getSession(String sessionId) async {
    // 先尝试从 .recp 文件获取完整信息
    try {
      final sessionDb = await openSession(sessionId);
      final session = await sessionDb.getSessionInfo();
      if (session != null) return session;
    } catch (_) {
      // 如果 .recp 文件打开失败，回退到摘要
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
  /// 同时更新 .recp 文件和全局摘要。
  Future<void> updateSession(Session session) async {
    final updatedSession = session.copyWith(
      updatedAt: DateTime.now(),
    );

    // 更新 .recp 文件
    final sessionDb = await openSession(session.sessionId);
    await sessionDb.saveSessionInfo(updatedSession);

    // 更新全局摘要
    await _configDb.updateSessionSummary(updatedSession);
  }

  /// 删除会话
  ///
  /// 删除 .recp 文件和全局摘要记录。
  Future<void> deleteSession(String sessionId) async {
    // 关闭并删除 .recp 文件
    await _closeSessionDatabase(sessionId);
    await _dbHelper.deleteSessionDatabase(sessionId);

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
  /// 遍历所有 .recp 文件计算总大小。
  Future<StorageStats> getStorageStats() async {
    final sessionsDir = await _dbHelper.sessionsPath;
    final dir = Directory(sessionsDir);

    int totalSize = 0;
    int sessionCount = 0;

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(AppConstants.recpFileExtension)) {
          sessionCount++;
          totalSize += await entity.length();
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
      // 记录旧缩略图大小
      final oldThumbnailSize = photo.thumbnail.length;

      // 使用原图重新生成更小的缩略图
      final newThumbnail = await ThumbnailUtil.generate(
        photo.data,
        maxSize: thumbnailMaxSize,
      );

      // 计算节省的空间
      if (newThumbnail.length < oldThumbnailSize) {
        savedBytes += oldThumbnailSize - newThumbnail.length;

        // 更新数据库中的缩略图
        final updatedPhoto = photo.copyWith(thumbnail: newThumbnail);
        await sessionDb.deletePhoto(photo.id);
        await sessionDb.insertPhoto(updatedPhoto);
      }
    }

    return savedBytes;
  }

  /// 获取所有会话的详细存储统计
  ///
  /// 遍历每个会话数据库，统计音频、照片、视频的占用空间。
  /// Author: GDNDZZK
  Future<StorageStats> getDetailedStorageStats() async {
    final sessions = await getAllSessions();
    int totalSize = 0;
    int audioSize = 0;
    int photosSize = 0;
    int videosSize = 0;

    for (final session in sessions) {
      try {
        final sessionDb = await openSession(session.sessionId);

        // 统计音频大小
        final audioChunks = await sessionDb.getAudioChunks();
        for (final chunk in audioChunks) {
          audioSize += chunk.data.length;
        }

        // 统计照片大小
        final photos = await sessionDb.getPhotos();
        for (final photo in photos) {
          photosSize += photo.data.length + photo.thumbnail.length;
        }

        // 统计视频大小
        final videoChunks = await sessionDb.getVideoChunks();
        for (final chunk in videoChunks) {
          videosSize += chunk.data.length + (chunk.thumbnail?.length ?? 0);
        }
      } catch (_) {
        // 忽略打开失败的会话
      }

      // 加上 .recp 文件本身的大小
      try {
        final sessionsDir = await _dbHelper.sessionsPath;
        final file = File(
          '$sessionsDir/${session.sessionId}${AppConstants.recpFileExtension}',
        );
        if (await file.exists()) {
          totalSize += await file.length();
        }
      } catch (_) {
        // 忽略文件大小获取失败
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

  /// 格式化两位数字
  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
