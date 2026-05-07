import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../models/session.dart';
import 'export_service.dart';

/// 外部会话管理服务
///
/// 负责管理从外部 .recp 文件打开的临时会话，包括：
/// - 打开外部文件并解压到 sessions 目录
/// - 标记和追踪外部会话状态
/// - 保存外部会话到永久会话列表
/// - 清理外部会话
/// - 检测孤立会话（上次未正常退出的外部会话）
class ExternalSessionService {
  final DatabaseHelper _dbHelper;
  final ExportService _exportService;

  ExternalSessionService(this._dbHelper, this._exportService);

  /// 打开外部 .recp 文件为临时会话
  ///
  /// [filePath] .recp 文件的本地路径
  ///
  /// 与 [ExportService.importSession] 的区别：
  /// - 不打开文件选择器，直接使用给定的文件路径
  /// - 不写入 session_summaries 表（不会出现在会话列表中）
  /// - 在 info 表中标记 is_external=true
  /// - 如果目标 sessionId 已存在且为外部会话，先清理旧的
  ///
  /// 返回解压后的 sessionId。
  Future<String> openExternalFile(String filePath) async {
    // 1. 验证文件格式
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 4) {
      throw Exception('文件太小，不是有效的 .recp 文件');
    }
    // ZIP 文件头为 PK\x03\x04 (0x50 0x4B 0x03 0x04)
    if (bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw Exception('无效的 .recp 文件格式（不是有效的 ZIP 文件）');
    }

    // 2. 解压 ZIP 文件，提取 sessionId
    final archive = ZipDecoder().decodeBytes(bytes);

    String? sessionId;
    for (final archiveFile in archive) {
      final parts = archiveFile.name.split('/');
      if (parts.isNotEmpty && parts.first.isNotEmpty) {
        sessionId = parts.first;
        break;
      }
    }

    if (sessionId == null || sessionId.isEmpty) {
      throw Exception('无法从文件中提取会话 ID');
    }

    // 3. 检查是否已存在
    final sessionDir = await _dbHelper.sessionDirPath(sessionId);
    if (await Directory(sessionDir).exists()) {
      // 检查是否为外部会话
      final isExternal = await isExternalSession(sessionId);
      if (isExternal) {
        // 清理旧的外部会话
        await cleanupExternalSession(sessionId);
      } else {
        throw Exception('会话已存在: $sessionId');
      }
    }

    // 4. 解压到 sessions 目录
    final sessionsPath = await _dbHelper.sessionsPath;
    for (final archiveFile in archive) {
      final outputPath = p.join(sessionsPath, archiveFile.name);
      if (archiveFile.isFile) {
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await File(outputPath).writeAsBytes(archiveFile.content as List<int>);
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }

    // 5. 验证解压后的数据库结构
    try {
      final db = await _dbHelper.openSessionDatabase(sessionId);

      // 检查是否有 info 表
      final tables = await db.query(
        'sqlite_master',
        where: "type = 'table' AND name = 'info'",
      );
      if (tables.isEmpty) {
        await _dbHelper.deleteSessionDirectory(sessionId);
        throw Exception('文件中未找到有效的会话数据（缺少 info 表）');
      }

      // 检查是否有 session_id
      final infoResults = await db.query(
        'info',
        where: 'key = ?',
        whereArgs: ['session_id'],
      );
      if (infoResults.isEmpty) {
        await _dbHelper.deleteSessionDirectory(sessionId);
        throw Exception('文件中未找到有效的会话信息');
      }
    } catch (e) {
      if (e.toString().contains('未找到有效的会话')) {
        rethrow;
      }
      await _dbHelper.deleteSessionDirectory(sessionId);
      throw Exception('无法读取会话数据: $e');
    }

    // 6. 在 info 表中标记 is_external=true
    final db = await _dbHelper.openSessionDatabase(sessionId);
    await db.insert(
      'info',
      {'key': AppConstants.infoKeyIsExternal, 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return sessionId;
  }

  /// 保存外部会话到永久会话列表
  ///
  /// 将会话信息写入 session_summaries 表，并移除外部标记。
  /// 保存后该会话将出现在会话列表中。
  ///
  /// [sessionId] 要保存的外部会话 ID
  Future<void> saveExternalSession(String sessionId) async {
    final db = await _dbHelper.openSessionDatabase(sessionId);

    // 读取 info 表获取会话信息
    final infoResults = await db.query('info');
    final infoMap = <String, String>{};
    for (final row in infoResults) {
      infoMap[row['key'] as String] = row['value'] as String;
    }

    if (infoMap.containsKey('session_id')) {
      final session = Session.fromInfoMap(infoMap);
      final configDb = await _dbHelper.openConfigDatabase();
      await configDb.insert(
        'session_summaries',
        {
          'session_id': session.sessionId,
          'title': session.title,
          'description': session.description,
          'created_at': session.createdAt.millisecondsSinceEpoch,
          'updated_at': session.updatedAt.millisecondsSinceEpoch,
          'duration': session.duration,
          'audio_duration': session.audioDuration,
          'event_count': session.eventCount,
          'tags': session.tags.join(','),
          'thumbnail': session.thumbnail,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // 清除外部标记和脏标记
    await clearExternalFlags(sessionId);
  }

  /// 将外部会话重新打包为 .recp 文件并调起系统分享
  ///
  /// [sessionId] 要分享的外部会话 ID
  /// [title] 会话标题（用于生成友好的文件名）
  Future<void> shareExternalSession(String sessionId, {String? title}) async {
    await _exportService.shareSession(sessionId, title: title);
  }

  /// 清理外部会话
  ///
  /// 删除指定外部会话的所有文件和数据库记录。
  /// 包括 sessions/{sessionId}/ 目录和 session_summaries 中的记录。
  ///
  /// [sessionId] 要清理的外部会话 ID
  Future<void> cleanupExternalSession(String sessionId) async {
    // 关闭数据库连接
    await _dbHelper.closeSessionDatabase(sessionId);

    // 删除整个会话目录
    final sessionDir = await _dbHelper.sessionDirPath(sessionId);
    final dir = Directory(sessionDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // 确保从 session_summaries 中也删除（防止残留）
    final configDb = await _dbHelper.openConfigDatabase();
    await configDb.delete(
      'session_summaries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 查找孤立的外部会话
  ///
  /// 扫描 sessions 目录，找出存在于目录中但不在 session_summaries 表中的会话，
  /// 且在 info 表中标记为 is_external=true 的会话。
  ///
  /// 返回孤立外部会话的 sessionId 列表。
  Future<List<String>> findOrphanedExternalSessions() async {
    final sessionsPath = await _dbHelper.sessionsPath;
    final sessionsDir = Directory(sessionsPath);

    if (!await sessionsDir.exists()) return [];

    // 获取 session_summaries 中所有 sessionId
    final configDb = await _dbHelper.openConfigDatabase();
    final summaries = await configDb.query('session_summaries');
    final summaryIds = summaries.map((row) => row['session_id'] as String).toSet();

    // 扫描 sessions 目录
    final orphanedIds = <String>[];
    await for (final entity in sessionsDir.list()) {
      if (entity is Directory) {
        final dirName = p.basename(entity.path);
        // 跳过已在摘要表中的会话
        if (summaryIds.contains(dirName)) continue;

        // 检查是否为外部会话
        try {
          if (await isExternalSession(dirName)) {
            orphanedIds.add(dirName);
          }
        } catch (_) {
          // 无法读取数据库，跳过
        }
      }
    }

    return orphanedIds;
  }

  /// 检查指定会话是否为外部会话
  ///
  /// 读取 session.db 的 info 表中 is_external 标记。
  Future<bool> isExternalSession(String sessionId) async {
    try {
      final db = await _dbHelper.openSessionDatabase(sessionId);
      final results = await db.query(
        'info',
        where: 'key = ?',
        whereArgs: [AppConstants.infoKeyIsExternal],
      );
      if (results.isEmpty) return false;
      return (results.first['value'] as String) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 检查指定会话是否有未保存的修改
  ///
  /// 读取 session.db 的 info 表中 is_dirty 标记。
  Future<bool> hasUnsavedChanges(String sessionId) async {
    try {
      final db = await _dbHelper.openSessionDatabase(sessionId);
      final results = await db.query(
        'info',
        where: 'key = ?',
        whereArgs: [AppConstants.infoKeyIsDirty],
      );
      if (results.isEmpty) return false;
      return (results.first['value'] as String) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 标记外部会话为脏状态（有未保存的修改）
  ///
  /// 在 session.db 的 info 表中设置 is_dirty=true。
  Future<void> markDirty(String sessionId) async {
    final db = await _dbHelper.openSessionDatabase(sessionId);
    await db.insert(
      'info',
      {'key': AppConstants.infoKeyIsDirty, 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 清除外部会话标记
  ///
  /// 移除 info 表中的 is_external 和 is_dirty 标记。
  /// 通常在保存外部会话为永久会话后调用。
  Future<void> clearExternalFlags(String sessionId) async {
    final db = await _dbHelper.openSessionDatabase(sessionId);
    await db.delete(
      'info',
      where: 'key IN (?, ?)',
      whereArgs: [AppConstants.infoKeyIsExternal, AppConstants.infoKeyIsDirty],
    );
  }
}
