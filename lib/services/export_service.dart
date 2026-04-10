import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
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
/// 导出格式为 ZIP 文件（.recp），包含整个会话目录。
/// 导入时解压 ZIP 文件到 sessions 目录。
/// Author: GDNDZZK
class ExportService {
  final DatabaseHelper _dbHelper;

  ExportService(this._dbHelper);

  /// 导出会话为 .recp 文件（ZIP 格式）
  ///
  /// [sessionId] 要导出的会话 ID
  ///
  /// 将整个会话目录打包为 ZIP 文件，复制到临时目录，返回导出文件路径。
  Future<String> exportSession(String sessionId) async {
    // 1. 获取会话目录路径
    final sessionDir = await _dbHelper.sessionDirPath(sessionId);
    final dir = Directory(sessionDir);
    if (!await dir.exists()) {
      throw Exception('会话目录不存在: $sessionId');
    }

    // 2. 创建 ZIP 归档
    final archive = Archive();
    await _addDirectoryToArchive(archive, dir, sessionId);

    // 3. 编码为 ZIP 数据
    final zipData = Uint8List.fromList(ZipEncoder().encode(archive)!);

    // 4. 写入临时目录
    final exportDir = await getTemporaryDirectory();
    final exportPath = p.join(
      exportDir.path,
      '$sessionId${AppConstants.recpFileExtension}',
    );
    await File(exportPath).writeAsBytes(zipData, flush: true);

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
  /// 打开文件选择器，选择 .recp 文件（ZIP 格式），解压到 sessions 目录。
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

    // 2. 验证文件格式（检查是否为有效 ZIP）
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    if (bytes.length < 4) {
      throw Exception('文件太小，不是有效的 .recp 文件');
    }
    // ZIP 文件头为 PK\x03\x04 (0x50 0x4B 0x03 0x04)
    if (bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw Exception('无效的 .recp 文件格式（不是有效的 ZIP 文件）');
    }

    // 3. 解压 ZIP 文件
    final archive = ZipDecoder().decodeBytes(bytes);

    // 从 ZIP 内的路径提取 session ID（第一级目录名）
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

    // 4. 检查是否已存在
    final sessionDir = await _dbHelper.sessionDirPath(sessionId);
    if (await Directory(sessionDir).exists()) {
      throw Exception('会话已存在: $sessionId');
    }

    // 5. 解压到 sessions 目录
    final sessionsPath = await _dbHelper.sessionsPath;
    for (final archiveFile in archive) {
      final outputPath = p.join(sessionsPath, archiveFile.name);
      if (archiveFile.isFile) {
        // 确保目录存在
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await File(outputPath).writeAsBytes(archiveFile.content as List<int>);
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }

    // 6. 验证解压后的数据库结构
    try {
      final db = await _dbHelper.openSessionDatabase(sessionId);

      // 检查是否有 info 表
      final tables = await db.query(
        'sqlite_master',
        where: "type = 'table' AND name = 'info'",
      );
      if (tables.isEmpty) {
        // 清理无效导入
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
      // 如果是自定义异常，重新抛出
      if (e.toString().contains('未找到有效的会话')) {
        rethrow;
      }
      // 清理无效导入
      await _dbHelper.deleteSessionDirectory(sessionId);
      throw Exception('无法读取会话数据: $e');
    }

    // 7. 从导入的数据库中读取会话信息，保存到全局摘要
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

  /// 递归添加目录内容到归档
  Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory dir,
    String basePath,
  ) async {
    await for (final entity in dir.list()) {
      if (entity is File) {
        final relativePath = p.join(
          basePath,
          entity.path.substring(dir.path.length + 1),
        );
        final data = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, data.length, data));
      } else if (entity is Directory) {
        final dirName = p.basename(entity.path);
        await _addDirectoryToArchive(
          archive,
          entity,
          p.join(basePath, dirName),
        );
      }
    }
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '_').trim();
  }
}
