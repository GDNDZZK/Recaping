import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/session_database.dart';
import '../models/ai_result.dart';
import '../services/ai_service.dart';
import 'settings_provider.dart';

/// AI 服务 Provider（依赖设置中的 API 配置）
///
/// 当 API 配置完整时返回 [AiService] 实例，否则返回 null。
/// Author: GDNDZZK
final aiServiceProvider = FutureProvider<AiService?>((ref) async {
  final aiSettings = ref.watch(aiSettingsProvider);
  final baseUrl = aiSettings['apiBaseUrl'];
  final apiKey = aiSettings['apiKey'];
  final model = aiSettings['model'];

  if (baseUrl == null || baseUrl.isEmpty ||
      apiKey == null || apiKey.isEmpty ||
      model == null || model.isEmpty) {
    return null; // API 未配置
  }

  return AiService(baseUrl: baseUrl, apiKey: apiKey, model: model);
});

/// AI 任务状态
///
/// Author: GDNDZZK
enum AiTaskState {
  /// 空闲
  idle,

  /// 加载中
  loading,

  /// 成功
  success,

  /// 错误
  error,
}

/// AI 任务状态 Notifier
///
/// 管理 AI 任务的执行状态。
/// Author: GDNDZZK
class AiTaskNotifier extends StateNotifier<AiTaskState> {
  AiTaskNotifier() : super(AiTaskState.idle);

  /// 设置为加载中状态
  void setLoading() => state = AiTaskState.loading;

  /// 设置为成功状态
  void setSuccess() => state = AiTaskState.success;

  /// 设置为错误状态
  void setError() => state = AiTaskState.error;

  /// 重置为空闲状态
  void reset() => state = AiTaskState.idle;
}

/// AI 任务状态 Provider
///
/// Author: GDNDZZK
final aiTaskStateProvider =
    StateNotifierProvider<AiTaskNotifier, AiTaskState>(
  (ref) => AiTaskNotifier(),
);

/// AI 加载提示文字 Provider
///
/// Author: GDNDZZK
final aiLoadingMessageProvider = StateProvider<String>((ref) => '正在处理...');

/// AI 结果列表 Provider（按会话 ID）
///
/// 从数据库加载指定会话的 AI 结果列表。
/// Author: GDNDZZK
final aiResultsProvider =
    FutureProvider.family<List<AiResult>, String>((ref, sessionId) async {
  final sessionDb = await SessionDatabase.create(sessionId);
  return sessionDb.getAiResults();
});

/// AI 结果列表刷新触发器
///
/// 修改此值可触发 aiResultsProvider 重新加载。
/// Author: GDNDZZK
final aiResultsRefreshProvider = StateProvider<int>((ref) => 0);

/// AI 结果列表 Provider（带刷新功能）
///
/// 监听 [aiResultsRefreshProvider] 的变化自动刷新。
/// Author: GDNDZZK
final aiResultsRefreshableProvider =
    FutureProvider.family<List<AiResult>, String>((ref, sessionId) async {
  // 监听刷新触发器
  ref.watch(aiResultsRefreshProvider);
  final sessionDb = await SessionDatabase.create(sessionId);
  return sessionDb.getAiResults();
});
