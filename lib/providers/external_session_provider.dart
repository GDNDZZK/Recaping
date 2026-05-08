import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../services/export_service.dart';
import '../services/external_session_service.dart';
import 'session_provider.dart';

/// 外部会话状态
///
/// 跟踪当前打开的外部会话信息，包括加载状态、脏标记等。
class ExternalSessionState {
  /// 当前打开的外部会话 ID，null 表示没有打开的外部会话
  final String? activeSessionId;

  /// 是否有未保存的修改
  final bool isDirty;

  /// 是否正在加载
  final bool isLoading;

  /// 正在加载的文件路径
  final String? loadingFilePath;

  /// 原始外部文件路径，用于保存回文件
  final String? sourceFilePath;

  /// 错误信息
  final String? error;

  const ExternalSessionState({
    this.activeSessionId,
    this.isDirty = false,
    this.isLoading = false,
    this.loadingFilePath,
    this.sourceFilePath,
    this.error,
  });

  /// 创建初始状态
  const ExternalSessionState.initial()
      : activeSessionId = null,
        isDirty = false,
        isLoading = false,
        loadingFilePath = null,
        sourceFilePath = null,
        error = null;

  /// 复制并修改部分字段
  ExternalSessionState copyWith({
    String? activeSessionId,
    bool? isDirty,
    bool? isLoading,
    String? loadingFilePath,
    String? sourceFilePath,
    String? error,
  }) {
    return ExternalSessionState(
      activeSessionId: activeSessionId ?? this.activeSessionId,
      isDirty: isDirty ?? this.isDirty,
      isLoading: isLoading ?? this.isLoading,
      loadingFilePath: loadingFilePath ?? this.loadingFilePath,
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      error: error,
    );
  }

  /// 是否有活跃的外部会话
  bool get hasActiveSession => activeSessionId != null;
}

/// 外部会话服务 Provider
///
/// 异步初始化 [ExternalSessionService]，依赖 [DatabaseHelper] 和 [ExportService]。
final externalSessionServiceProvider = FutureProvider<ExternalSessionService>((ref) async {
  final dbHelper = DatabaseHelper();
  final exportService = await ref.watch(exportServiceProvider.future);
  return ExternalSessionService(dbHelper, exportService);
});

/// 外部会话 Notifier
///
/// 管理外部会话的完整生命周期，包括：
/// - 接收并处理外部 .recp 文件
/// - 跟踪外部会话状态（加载中、活跃、脏）
/// - 保存外部会话到永久列表
/// - 清理外部会话资源
/// - 检测并恢复孤立会话
class ExternalSessionNotifier extends StateNotifier<ExternalSessionState> {
  final Ref _ref;

  /// 处理锁，防止并发处理多个外部文件
  bool _isProcessing = false;

  ExternalSessionNotifier(this._ref) : super(const ExternalSessionState.initial());

  /// 处理外部文件
  ///
  /// [filePath] 外部 .recp 文件的本地路径
  ///
  /// 将文件解压到 sessions 目录并标记为外部会话。
  /// 处理过程中会设置 isLoading 状态，成功后设置 activeSessionId。
  /// 返回解压后的 sessionId，失败返回 null。
  Future<String?> handleIncomingFile(String filePath) async {
    debugPrint('[ExternalSession] handleIncomingFile 开始: $filePath');
    // 防止并发处理
    if (_isProcessing) {
      debugPrint('[ExternalSession] 正在处理其他文件，跳过');
      return null;
    }
    _isProcessing = true;

    try {
      state = state.copyWith(
        isLoading: true,
        loadingFilePath: filePath,
        error: null,
      );

      debugPrint('[ExternalSession] 等待 ExternalSessionService 初始化...');
      final service = await _ref.read(externalSessionServiceProvider.future);
      debugPrint('[ExternalSession] Service 就绪，开始打开文件...');
      final sessionId = await service.openExternalFile(filePath);
      debugPrint('[ExternalSession] 文件打开成功，sessionId=$sessionId');

      if (mounted) {
        state = ExternalSessionState(
          activeSessionId: sessionId,
          isDirty: false,
          isLoading: false,
          sourceFilePath: filePath,
        );
      }

      return sessionId;
    } catch (e, stackTrace) {
      debugPrint('[ExternalSession] handleIncomingFile 失败: $e');
      debugPrint('[ExternalSession] 堆栈: $stackTrace');
      if (mounted) {
        state = ExternalSessionState(
          isLoading: false,
          error: e.toString(),
        );
      }
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// 标记当前外部会话为脏状态（有未保存的修改）
  ///
  /// 先更新内存状态确保 UI 能立即响应，再异步持久化到数据库。
  /// 即使数据库写入失败，内存中的 isDirty 标记仍然有效。
  Future<void> markDirty() async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return;

    // 先更新内存状态，确保 UI 能正确响应（如返回时的保存确认弹窗）
    if (mounted) {
      state = state.copyWith(isDirty: true);
    }

    // 再持久化到数据库（失败不影响内存状态）
    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      await service.markDirty(sessionId);
    } catch (e) {
      debugPrint('[ExternalSession] markDirty 持久化失败: $e');
    }
  }

  /// 保存外部会话到永久会话列表
  ///
  /// 将当前外部会话写入 session_summaries 表并清除外部标记。
  /// 保存成功后会话将出现在会话列表中。
  /// 同时刷新会话列表。
  Future<bool> saveSession() async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return false;

    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      await service.saveExternalSession(sessionId);

      // 刷新会话列表
      await _ref.read(sessionListProvider.notifier).loadSessions();

      if (mounted) {
        state = state.copyWith(isDirty: false);
      }
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
      return false;
    }
  }

  /// 清理当前外部会话
  ///
  /// 删除外部会话的所有文件和数据库记录，并重置状态。
  Future<void> cleanup() async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return;

    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      await service.cleanupExternalSession(sessionId);
    } catch (_) {
      // 清理失败时忽略，仍然重置状态
    }

    if (mounted) {
      state = const ExternalSessionState.initial();
    }
  }

  /// 检查并返回孤立的外部会话列表
  ///
  /// 扫描 sessions 目录，找出未正常关闭的外部会话。
  /// 返回孤立会话的 sessionId 列表。
  Future<List<String>> checkAndRecoverOrphanedSessions() async {
    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      return service.findOrphanedExternalSessions();
    } catch (_) {
      return [];
    }
  }

  /// 恢复指定的孤立会话到永久列表
  ///
  /// [sessionId] 要恢复的孤立会话 ID
  ///
  /// 将孤立会话写入 session_summaries 表并清除外部标记。
  Future<bool> recoverOrphanedSession(String sessionId) async {
    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      await service.saveExternalSession(sessionId);

      // 刷新会话列表
      await _ref.read(sessionListProvider.notifier).loadSessions();

      return true;
    } catch (_) {
      return false;
    }
  }

  /// 放弃指定的孤立会话
  ///
  /// [sessionId] 要放弃的孤立会话 ID
  ///
  /// 删除孤立会话的所有文件和数据库记录。
  Future<void> discardOrphanedSession(String sessionId) async {
    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      await service.cleanupExternalSession(sessionId);
    } catch (_) {
      // 忽略清理失败
    }
  }

  /// 保存回原始外部文件
  ///
  /// 尝试将会话重新打包为 .recp 文件并写回 [state.sourceFilePath]。
  /// 成功返回 true 并清除脏标记，失败返回 false。
  Future<bool> saveBackToFile() async {
    final sessionId = state.activeSessionId;
    final targetPath = state.sourceFilePath;
    if (sessionId == null || targetPath == null) return false;

    try {
      final service = await _ref.read(externalSessionServiceProvider.future);
      final success = await service.saveBackToFile(sessionId, targetPath);
      if (success && mounted) {
        state = state.copyWith(isDirty: false);
      }
      return success;
    } catch (e) {
      debugPrint('[ExternalSession] saveBackToFile 失败: $e');
      return false;
    }
  }

  /// 另存为文件到指定目录
  ///
  /// 使用 ExportService 重新打包为 .recp 文件，
  /// 然后保存到指定的目录。
  /// 成功返回保存路径，失败返回 null。
  ///
  /// [directory] 目标目录路径
  /// [fileName] 文件名，必须包含 .recp 扩展名
  Future<String?> saveAsFileToDirectory(String directory, String fileName) async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return null;

    try {
      // 1. 使用 ExportService 生成临时 .recp 文件
      final exportService = await _ref.read(exportServiceProvider.future);
      final exportPath = await exportService.exportSession(sessionId);
      debugPrint('[ExternalSession] saveAsFileToDirectory: 临时导出文件 $exportPath');

      final exportFile = File(exportPath);
      if (!await exportFile.exists()) {
        debugPrint('[ExternalSession] saveAsFileToDirectory: 临时导出文件不存在');
        return null;
      }

      // 2. 确保文件名以 .recp 结尾
      if (!fileName.endsWith(AppConstants.recpFileExtension)) {
        fileName = '$fileName${AppConstants.recpFileExtension}';
      }

      // 3. 拼接目标路径
      final targetPath = p.join(directory, fileName);
      debugPrint('[ExternalSession] saveAsFileToDirectory: 目标路径 $targetPath');

      // 4. 将临时文件复制到目标路径
      await exportFile.copy(targetPath);
      debugPrint('[ExternalSession] saveAsFileToDirectory: 文件复制成功');

      // 5. 删除临时文件
      try {
        await exportFile.delete();
        debugPrint('[ExternalSession] saveAsFileToDirectory: 临时文件已删除');
      } catch (e) {
        debugPrint('[ExternalSession] saveAsFileToDirectory: 删除临时文件失败（可忽略）: $e');
      }

      debugPrint('[ExternalSession] saveAsFileToDirectory: 文件保存成功 $targetPath');

      if (mounted) {
        state = state.copyWith(isDirty: false);
      }
      return targetPath;
    } catch (e) {
      debugPrint('[ExternalSession] saveAsFileToDirectory 失败: $e');
      return null;
    }
  }

  /// 另存为文件
  ///
  /// 使用 ExportService 重新打包为 .recp 文件，
  /// 然后让用户选择保存目录，手动复制文件到目标路径。
  /// 成功返回保存路径，失败返回 null。
  ///
  /// [fileName] 可选参数，如果提供则使用该文件名，否则使用默认文件名。
  /// 默认文件名优先使用原始打开文件的文件名，
  /// 其次使用会话标题，最后回退到 session ID。
  ///
  /// 此方法使用 `FilePicker.platform.getDirectoryPath()` 选择目录，
  /// 完全绕过 SAF 的 MIME 类型检测，避免 .zip 后缀问题。
  Future<String?> saveAsFile({String? fileName}) async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return null;

    try {
      // 1. 让用户选择保存目录
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: '选择保存目录',
      );

      if (selectedDirectory == null) {
        debugPrint('[ExternalSession] saveAsFile: 用户取消了目录选择');
        return null;
      }

      debugPrint('[ExternalSession] saveAsFile: 用户选择目录 $selectedDirectory');

      // 2. 确定文件名：如果未提供，则使用默认文件名
      if (fileName == null || fileName.isEmpty) {
        fileName = _getDefaultFileName(sessionId);
      }

      // 3. 调用 saveAsFileToDirectory 保存文件
      return await saveAsFileToDirectory(selectedDirectory, fileName);
    } catch (e) {
      debugPrint('[ExternalSession] saveAsFile 失败: $e');
      return null;
    }
  }

  /// 获取默认文件名
  ///
  /// 优先使用原始打开文件的文件名，其次使用会话标题，最后回退到 session ID。
  String _getDefaultFileName(String sessionId) {
    // 优先使用原始文件名
    final sourcePath = state.sourceFilePath;
    if (sourcePath != null &&
        p.basename(sourcePath).endsWith(AppConstants.recpFileExtension)) {
      return p.basename(sourcePath);
    }

    // 尝试使用会话标题
    final sessionList = _ref.read(sessionListProvider).valueOrNull;
    final session = sessionList?.where((s) => s.sessionId == sessionId).firstOrNull;
    final title = session?.title;
    if (title != null && title.isNotEmpty) {
      final sanitized =
          title.replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '_').trim();
      return '$sanitized${AppConstants.recpFileExtension}';
    }

    // 回退到 session ID
    return '$sessionId${AppConstants.recpFileExtension}';
  }

  /// 清除错误状态
  void clearError() {
    if (mounted && state.error != null) {
      state = state.copyWith(error: null);
    }
  }
}

/// 外部会话 Provider
///
/// 提供 [ExternalSessionNotifier] 实例，用于管理外部会话状态。
final externalSessionProvider =
    StateNotifierProvider<ExternalSessionNotifier, ExternalSessionState>((ref) {
  return ExternalSessionNotifier(ref);
});
