import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/config_database.dart';
import '../core/database/database_helper.dart';
import '../models/session.dart';
import '../services/storage_service.dart';
import 'settings_provider.dart';

/// 存储服务 Provider
///
/// 异步初始化 [StorageService]，依赖 [DatabaseHelper] 和 [ConfigDatabase]。
/// Author: GDNDZZK
final storageServiceProvider = FutureProvider<StorageService>((ref) async {
  final dbHelper = DatabaseHelper();
  final configDb = await ref.watch(configDbProvider.future);
  return StorageService(dbHelper, configDb);
});

/// 会话列表 Notifier
///
/// 管理会话列表的加载、创建、删除、更新和搜索操作。
/// Author: GDNDZZK
class SessionListNotifier extends StateNotifier<AsyncValue<List<Session>>> {
  final Ref _ref;

  SessionListNotifier(this._ref) : super(const AsyncValue.data([])) {
    // 初始化时自动加载会话列表
    loadSessions();
  }

  /// 加载所有会话列表
  ///
  /// 从全局配置数据库获取会话摘要列表。
  Future<void> loadSessions() async {
    try {
      state = const AsyncValue.loading();
      final storageService = await _ref.read(storageServiceProvider.future);
      final sessions = await storageService.getAllSessions();
      if (mounted) {
        state = AsyncValue.data(sessions);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// 创建新会话
  ///
  /// [title] 会话标题（可选，默认使用日期时间格式）
  ///
  /// 创建成功后自动刷新会话列表。
  Future<Session?> createSession({String? title}) async {
    try {
      final storageService = await _ref.read(storageServiceProvider.future);
      final session = await storageService.createSession(title: title);
      await loadSessions();
      return session;
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
      return null;
    }
  }

  /// 删除会话
  ///
  /// [sessionId] 要删除的会话 ID
  ///
  /// 删除成功后自动刷新会话列表。
  Future<void> deleteSession(String sessionId) async {
    try {
      final storageService = await _ref.read(storageServiceProvider.future);
      await storageService.deleteSession(sessionId);
      await loadSessions();
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// 更新会话信息
  ///
  /// [session] 要更新的会话对象
  ///
  /// 更新成功后自动刷新会话列表。
  Future<void> updateSession(Session session) async {
    try {
      final storageService = await _ref.read(storageServiceProvider.future);
      await storageService.updateSession(session);
      await loadSessions();
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// 搜索会话
  ///
  /// [query] 搜索关键词，匹配标题和描述
  Future<void> searchSessions(String query) async {
    try {
      state = const AsyncValue.loading();
      final storageService = await _ref.read(storageServiceProvider.future);
      final results = await storageService.searchSessions(query);
      if (mounted) {
        state = AsyncValue.data(results);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// 会话列表 Provider
///
/// Author: GDNDZZK
final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, AsyncValue<List<Session>>>((ref) {
  return SessionListNotifier(ref);
});

/// 存储统计 Notifier
///
/// 管理存储空间统计信息的获取和刷新。
/// Author: GDNDZZK
class StorageStatsNotifier extends StateNotifier<AsyncValue<StorageStats?>> {
  final Ref _ref;

  StorageStatsNotifier(this._ref) : super(const AsyncValue.data(null));

  /// 刷新存储统计信息
  Future<void> refresh() async {
    try {
      state = const AsyncValue.loading();
      final storageService = await _ref.read(storageServiceProvider.future);
      final stats = await storageService.getStorageStats();
      if (mounted) {
        state = AsyncValue.data(stats);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// 存储统计 Provider
///
/// Author: GDNDZZK
final storageStatsProvider =
    StateNotifierProvider<StorageStatsNotifier, AsyncValue<StorageStats?>>((ref) {
  return StorageStatsNotifier(ref);
});
