import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../models/session.dart';
import 'database_helper.dart';

/// 全局配置数据库操作类
///
/// 管理应用全局配置（音频格式、主题、AI API 配置等）
/// 和会话摘要列表（用于首页展示，避免打开每个 .recp 文件）。
/// Author: GDNDZZK
class ConfigDatabase {
  final Database _db;

  ConfigDatabase._(this._db);

  /// 创建 ConfigDatabase 实例
  static Future<ConfigDatabase> create() async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.openConfigDatabase();
    return ConfigDatabase._(db);
  }

  /// 从已有的 Database 实例创建
  static ConfigDatabase fromDatabase(Database db) {
    return ConfigDatabase._(db);
  }

  // ==================== 配置项 CRUD ====================

  /// 设置配置项
  Future<void> setConfig(String key, String value) async {
    await _db.insert(
      'configs',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取配置项
  Future<String?> getConfig(String key) async {
    final results = await _db.query(
      'configs',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String;
  }

  /// 获取所有配置项
  Future<Map<String, String>> getAllConfigs() async {
    final results = await _db.query('configs');
    return {
      for (final row in results) row['key'] as String: row['value'] as String,
    };
  }

  /// 删除配置项
  Future<void> deleteConfig(String key) async {
    await _db.delete('configs', where: 'key = ?', whereArgs: [key]);
  }

  // ==================== 便捷方法 - 音频配置 ====================

  /// 设置音频格式
  Future<void> setAudioFormat(String format) async {
    await setConfig('audio_format', format);
  }

  /// 获取音频格式
  Future<String> getAudioFormat() async {
    return await getConfig('audio_format') ?? 'aac';
  }

  /// 设置采样率
  Future<void> setSampleRate(int rate) async {
    await setConfig('sample_rate', rate.toString());
  }

  /// 获取采样率
  Future<int> getSampleRate() async {
    final value = await getConfig('sample_rate');
    return int.tryParse(value ?? '44100') ?? 44100;
  }

  // ==================== 便捷方法 - 主题配置 ====================

  /// 设置主题模式（light/dark/system）
  Future<void> setThemeMode(String mode) async {
    await setConfig('theme_mode', mode);
  }

  /// 获取主题模式
  Future<String> getThemeMode() async {
    return await getConfig('theme_mode') ?? 'system';
  }

  // ==================== 便捷方法 - AI API 配置 ====================

  /// 设置 AI API 基础 URL
  Future<void> setAiApiBaseUrl(String url) async {
    await setConfig('ai_api_base_url', url);
  }

  /// 获取 AI API 基础 URL
  Future<String?> getAiApiBaseUrl() async {
    return await getConfig('ai_api_base_url');
  }

  /// 设置 AI API Key
  Future<void> setAiApiKey(String key) async {
    await setConfig('ai_api_key', key);
  }

  /// 获取 AI API Key
  Future<String?> getAiApiKey() async {
    return await getConfig('ai_api_key');
  }

  /// 设置 AI 模型名称
  Future<void> setAiModel(String model) async {
    await setConfig('ai_model', model);
  }

  /// 获取 AI 模型名称
  Future<String?> getAiModel() async {
    return await getConfig('ai_model');
  }

  // ==================== 会话摘要操作 ====================

  /// 保存会话摘要（用于首页展示）
  Future<void> saveSessionSummary(Session session) async {
    await _db.insert(
      'session_summaries',
      _sessionToSummaryMap(session),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有会话摘要（按更新时间降序排序）
  Future<List<Session>> getSessionSummaries() async {
    final results = await _db.query(
      'session_summaries',
      orderBy: 'updated_at DESC',
    );
    return results.map((map) => _summaryMapToSession(map)).toList();
  }

  /// 删除会话摘要
  Future<void> deleteSessionSummary(String sessionId) async {
    await _db.delete(
      'session_summaries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 更新会话摘要
  Future<void> updateSessionSummary(Session session) async {
    await _db.update(
      'session_summaries',
      _sessionToSummaryMap(session),
      where: 'session_id = ?',
      whereArgs: [session.sessionId],
    );
  }

  /// 将 Session 转换为 session_summaries 表的 Map
  Map<String, dynamic> _sessionToSummaryMap(Session session) {
    return {
      'session_id': session.sessionId,
      'title': session.title,
      'description': session.description,
      'created_at': session.createdAt.millisecondsSinceEpoch,
      'updated_at': session.updatedAt.millisecondsSinceEpoch,
      'duration': session.duration,
      'audio_duration': session.audioDuration,
      'event_count': session.eventCount,
      'tags': session.tags.isNotEmpty
          ? '[${session.tags.map((t) => '"$t"').join(',')}]'
          : null,
      'thumbnail': session.thumbnail,
    };
  }

  /// 从 session_summaries 表的 Map 创建 Session 实例
  Session _summaryMapToSession(Map<String, dynamic> map) {
    return Session(
      sessionId: map['session_id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      duration: map['duration'] as int? ?? 0,
      audioDuration: map['audio_duration'] as int? ?? 0,
      eventCount: map['event_count'] as int? ?? 0,
      thumbnail: map['thumbnail'] as Uint8List?,
    );
  }
}
