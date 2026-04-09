import 'dart:io';

import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/database/config_database.dart';
import '../core/database/database_helper.dart';
import '../core/database/session_database.dart';
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
