import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../models/session.dart';

/// 导出导入服务
///
/// 管理会话的导出、导入和分享功能。
/// 支持将 .recp 文件导出到外部存储、通过系统分享面板分享、
/// 以及从外部文件导入会话。
/// Author: GDNDZZK
class ExportService {
  final DatabaseHelper _dbHelper;

  ExportService(this._dbHelper);

  /// 导出会话为 .recp 文件
  ///
  /// [sessionId] 要导出的会话 ID
  ///
  /// 将 .recp 文件复制到临时目录，返回导出文件路径。
  Future<String> exportSession(String sessionId) async {
    // 1. 获取源 .recp 文件路径
    final sessionsPath = await _dbHelper.sessionsPath;
    final sourcePath = p.join(
      sessionsPath,
      '$sessionId${AppConstants.recpFileExtension}',
    );

    // 2. 检查文件是否存在
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('会话文件不存在: $sessionId');
    }

    // 3. 复制到临时目录
    final exportDir = await getTemporaryDirectory();
    final exportPath = p.join(
      exportDir.path,
      '$sessionId${AppConstants.recpFileExtension}',
    );
    await sourceFile.copy(exportPath);

    return exportPath;
  }

  /// 导出会话并分享
  ///
  /// [sessionId] 要分享的会话 ID
  /// [title] 会话标题（用于生成友好的文件名）
  ///
  /// 使用系统分享面板分享 .recp 文件。
  Future<void> shareSession(String sessionId, {String? title}) async {
    final exportPath = await exportSession(sessionId);

    // 生成友好的文件名
    final fileName = title != null
        ? '${_sanitizeFileName(title)}${AppConstants.recpFileExtension}'
        : p.basename(exportPath);

    // 重命名文件为更友好的名称
    final dir = p.dirname(exportPath);
    final friendlyPath = p.join(dir, fileName);

    // 如果目标文件已存在，先删除
    final friendlyFile = File(friendlyPath);
    if (await friendlyFile.exists()) {
      await friendlyFile.delete();
    }
    await File(exportPath).rename(friendlyPath);

    await Share.shareXFiles(
      [XFile(friendlyPath)],
      text: 'Recaping 录音记录: ${title ?? sessionId}',
      subject: 'Recaping - $title',
    );
  }

  /// 从文件导入会话
  ///
  /// 打开文件选择器，选择 .recp 文件，验证格式后复制到 sessions 目录。
  /// 返回导入的会话 ID。
  Future<String> importSession() async {
    // 1. 打开文件选择器
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['recp'],
    );

    if (result == null || result.files.isEmpty) {
      throw Exception('未选择文件');
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      throw Exception('文件路径为空');
    }

    // 2. 验证文件格式（检查是否为有效 SQLite）
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    if (bytes.length < 16) {
      throw Exception('文件太小，不是有效的 .recp 文件');
    }
    // SQLite 文件头为 "SQLite format 3\000"
    final header = String.fromCharCodes(bytes.sublist(0, 15));
    if (!header.startsWith('SQLite format 3')) {
      throw Exception('无效的 .recp 文件格式');
    }

    // 3. 从文件名提取 session ID
    final fileName = p.basenameWithoutExtension(filePath);
    final sessionId = fileName;

    // 4. 验证数据库结构（尝试打开并读取 info 表）
    Database? tempDb;
    try {
      // 复制到临时位置进行验证
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(
        tempDir.path,
        'import_verify_$sessionId${AppConstants.recpFileExtension}',
      );
      await file.copy(tempPath);

      // 尝试打开数据库并读取会话信息
      tempDb = await openDatabase(
        tempPath,
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );

      // 检查是否有 info 表
      final tables = await tempDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='info'",
      );
      if (tables.isEmpty) {
        throw Exception('文件中未找到有效的会话数据（缺少 info 表）');
      }

      // 检查是否有 session_id
      final infoResults = await tempDb.query(
        'info',
        where: 'key = ?',
        whereArgs: ['session_id'],
      );
      if (infoResults.isEmpty) {
        throw Exception('文件中未找到有效的会话信息');
      }

      // 关闭临时数据库
      await tempDb.close();
      tempDb = null;

      // 清理临时文件
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      // 关闭临时数据库
      if (tempDb != null && tempDb.isOpen) {
        await tempDb.close();
      }
      // 如果是自定义异常，重新抛出
      if (e.toString().contains('未找到有效的会话')) {
        rethrow;
      }
      throw Exception('无法读取会话数据: $e');
    }

    // 5. 复制到 sessions 目录
    final sessionsPath = await _dbHelper.sessionsPath;
    final destPath = p.join(
      sessionsPath,
      '$sessionId${AppConstants.recpFileExtension}',
    );

    // 检查是否已存在
    if (await File(destPath).exists()) {
      throw Exception('会话已存在: $sessionId');
    }

    await file.copy(destPath);

    // 6. 从导入的数据库中读取会话信息，保存到全局摘要
    try {
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
    } catch (_) {
      // 导入成功但保存摘要失败，不影响主流程
    }

    return sessionId;
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '_').trim();
  }
}
