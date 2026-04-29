import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

/// 数据库辅助类
///
/// 负责管理数据库连接、目录结构和数据库文件的创建。
/// 使用单例模式确保全局只有一个实例。
///
/// 新方案：每个会话一个目录，数据库文件在目录内，媒体文件在子目录中。
/// Author: GDNDZZK
class DatabaseHelper {
  static DatabaseHelper? _instance;

  DatabaseHelper._();

  /// 获取单例实例
  factory DatabaseHelper() => _instance ??= DatabaseHelper._();

  /// 已打开的数据库连接缓存
  final Map<String, Database> _databases = {};

  /// 全局配置数据库实例
  Database? _configDatabase;

  /// 获取应用数据根目录
  Future<String> get appDataPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  /// 获取 sessions 目录路径
  Future<String> get sessionsPath async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, AppConstants.sessionsDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// 获取 temp 目录路径
  Future<String> get tempPath async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, AppConstants.tempDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// 获取 app_config.db 文件路径
  Future<String> get configDbPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, AppConstants.configDbName);
  }

  /// 获取会话目录路径
  ///
  /// [sessionId] 会话唯一标识
  /// 返回会话目录的绝对路径
  Future<String> sessionDirPath(String sessionId) async {
    final basePath = await sessionsPath;
    return p.join(basePath, sessionId);
  }

  /// 确保会话子目录存在
  ///
  /// 创建 audio/photos/videos/thumbnails 子目录。
  Future<void> ensureSessionDirs(String sessionId) async {
    final basePath = await sessionDirPath(sessionId);
    await Directory(p.join(basePath, 'audio')).create(recursive: true);
    await Directory(p.join(basePath, 'photos')).create(recursive: true);
    await Directory(p.join(basePath, 'videos')).create(recursive: true);
    await Directory(p.join(basePath, 'thumbnails')).create(recursive: true);
  }

  /// 打开或创建会话数据库（session.db）
  ///
  /// [sessionId] 会话唯一标识，用于构造目录和文件名
  /// 返回打开的 Database 实例
  Future<Database> openSessionDatabase(String sessionId) async {
    // 如果已缓存，直接返回
    if (_databases.containsKey(sessionId)) {
      return _databases[sessionId]!;
    }

    // 确保会话目录存在
    await ensureSessionDirs(sessionId);

    final sessionDir = await sessionDirPath(sessionId);
    final dbPath = p.join(sessionDir, 'session.db');

    final database = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _onSessionCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onSessionUpgrade,
    );

    _databases[sessionId] = database;
    return database;
  }

  /// 关闭指定会话的数据库连接
  Future<void> closeSessionDatabase(String sessionId) async {
    final database = _databases.remove(sessionId);
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  /// 打开或创建全局配置数据库
  Future<Database> openConfigDatabase() async {
    if (_configDatabase != null && _configDatabase!.isOpen) {
      return _configDatabase!;
    }

    final path = await configDbPath;
    _configDatabase = await openDatabase(
      path,
      version: 1,
      onCreate: _onConfigCreate,
      onConfigure: _onConfigure,
    );

    return _configDatabase!;
  }

  /// 关闭全局配置数据库
  Future<void> closeConfigDatabase() async {
    if (_configDatabase != null && _configDatabase!.isOpen) {
      await _configDatabase!.close();
      _configDatabase = null;
    }
  }

  /// 关闭所有数据库连接
  Future<void> closeAll() async {
    for (final database in _databases.values) {
      if (database.isOpen) {
        await database.close();
      }
    }
    _databases.clear();
    await closeConfigDatabase();
  }

  /// 删除指定会话的整个目录（包含数据库和所有媒体文件）
  Future<void> deleteSessionDirectory(String sessionId) async {
    await closeSessionDatabase(sessionId);

    final sessionDir = await sessionDirPath(sessionId);
    final dir = Directory(sessionDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 配置数据库（启用外键支持）
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// 创建会话数据库表结构
  Future<void> _onSessionCreate(Database db, int version) async {
    await db.transaction((txn) async {
      // info 表（key-value 存储）
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS info (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // 音频分片表（文件路径引用）
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS audio_chunks (
          id TEXT PRIMARY KEY,
          chunk_index INTEGER NOT NULL,
          start_time INTEGER NOT NULL,
          end_time INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          format TEXT NOT NULL DEFAULT 'aac',
          sample_rate INTEGER NOT NULL DEFAULT 44100,
          channels INTEGER NOT NULL DEFAULT 1
        )
      ''');

      // 视频分片表（文件路径引用）
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS video_chunks (
          id TEXT PRIMARY KEY,
          video_id TEXT NOT NULL,
          chunk_index INTEGER NOT NULL,
          start_time INTEGER NOT NULL,
          end_time INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          format TEXT NOT NULL DEFAULT 'mp4',
          thumbnail_path TEXT,
          title TEXT
        )
      ''');

      // 照片表（文件路径引用）
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS photos (
          id TEXT PRIMARY KEY,
          timestamp INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          thumbnail_path TEXT NOT NULL,
          format TEXT NOT NULL DEFAULT 'jpeg',
          width INTEGER NOT NULL DEFAULT 0,
          height INTEGER NOT NULL DEFAULT 0,
          title TEXT
        )
      ''');

      // 文字笔记表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS text_notes (
          id TEXT PRIMARY KEY,
          timestamp INTEGER NOT NULL,
          title TEXT,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');

      // 书签表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS bookmarks (
          id TEXT PRIMARY KEY,
          timestamp INTEGER NOT NULL,
          label TEXT,
          color TEXT NOT NULL DEFAULT '#FF6B6B',
          created_at INTEGER NOT NULL
        )
      ''');

      // AI 结果表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS ai_results (
          id TEXT PRIMARY KEY,
          task_type TEXT NOT NULL,
          result_text TEXT NOT NULL,
          model_name TEXT,
          created_at INTEGER NOT NULL
        )
      ''');

      // 创建索引
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_audio_chunks_chunk_index
        ON audio_chunks(chunk_index)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_audio_chunks_start_time
        ON audio_chunks(start_time)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_video_chunks_video_id
        ON video_chunks(video_id)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_photos_timestamp
        ON photos(timestamp)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_text_notes_timestamp
        ON text_notes(timestamp)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_bookmarks_timestamp
        ON bookmarks(timestamp)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_ai_results_task_type
        ON ai_results(task_type)
      ''');
    });
  }

  /// 会话数据库升级迁移
  Future<void> _onSessionUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE photos ADD COLUMN title TEXT');
        await txn.execute('ALTER TABLE video_chunks ADD COLUMN title TEXT');
      });
    }
  }

  /// 创建全局配置数据库表结构
  Future<void> _onConfigCreate(Database db, int version) async {
    await db.transaction((txn) async {
      // 配置项表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS configs (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // 会话摘要表（用于首页展示）
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS session_summaries (
          session_id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          duration INTEGER NOT NULL DEFAULT 0,
          audio_duration INTEGER NOT NULL DEFAULT 0,
          event_count INTEGER NOT NULL DEFAULT 0,
          tags TEXT,
          thumbnail BLOB
        )
      ''');

      // 创建索引
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_session_summaries_updated_at
        ON session_summaries(updated_at)
      ''');
    });
  }
}
