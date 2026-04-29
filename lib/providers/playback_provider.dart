import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/session_database.dart';
import '../models/bookmark.dart';
import '../models/photo.dart';
import '../models/text_note.dart';
import '../models/timeline_event.dart';
import '../models/video_chunk.dart';
import '../services/audio_playback_service.dart';
import '../services/timeline_service.dart';
import 'session_provider.dart';

/// 音频回放服务 Provider
///
/// 提供 [AudioPlaybackService] 单例，在 Provider 销毁时自动释放资源。
/// Author: GDNDZZK
final playbackServiceProvider = Provider<AudioPlaybackService>((ref) {
  final service = AudioPlaybackService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 回放状态 Provider
///
/// 监听 [AudioPlaybackService.onStateChanged] 流，自动更新播放状态。
/// Author: GDNDZZK
final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  final service = ref.watch(playbackServiceProvider);
  return service.onStateChanged;
});

/// 当前播放位置 Provider
///
/// 监听 [AudioPlaybackService.onPositionChanged] 流，返回当前播放位置。
/// Author: GDNDZZK
final playbackPositionProvider = StreamProvider<Duration>((ref) {
  final service = ref.watch(playbackServiceProvider);
  return service.onPositionChanged;
});

/// 总时长 Provider
///
/// 返回当前加载音频的总时长。
/// Author: GDNDZZK
final playbackDurationProvider = Provider<Duration>((ref) {
  final service = ref.watch(playbackServiceProvider);
  return service.duration;
});

/// 播放速度 Notifier
///
/// 管理播放速度的设置。
/// Author: GDNDZZK
class PlaybackSpeedNotifier extends StateNotifier<double> {
  final Ref _ref;

  PlaybackSpeedNotifier(this._ref) : super(1.0);

  /// 设置播放速度
  ///
  /// [speed] 播放速度（1.0 为正常速度）
  Future<void> setSpeed(double speed) async {
    final service = _ref.read(playbackServiceProvider);
    await service.setSpeed(speed);
    if (mounted) {
      state = speed;
    }
  }
}

/// 播放速度 Provider
///
/// Author: GDNDZZK
final playbackSpeedProvider =
    StateNotifierProvider<PlaybackSpeedNotifier, double>((ref) {
  return PlaybackSpeedNotifier(ref);
});

/// 回放时间轴事件 Notifier
///
/// 管理回放会话的时间轴事件列表，支持编辑和删除操作。
/// Author: GDNDZZK
class PlaybackEventsNotifier extends StateNotifier<AsyncValue<List<TimelineEvent>>> {
  final Ref _ref;

  /// 保存的会话 ID，用于刷新事件列表
  String? _sessionId;

  /// 保存的数据库引用，用于创建 TimelineService 实例
  SessionDatabase? _database;

  PlaybackEventsNotifier(this._ref) : super(const AsyncValue.data([]));

  /// 加载指定会话的时间轴事件
  ///
  /// [sessionId] 会话 ID
  Future<void> loadEvents(String sessionId) async {
    try {
      state = const AsyncValue.loading();

      final storageService = await _ref.read(storageServiceProvider.future);
      final sessionDb = await storageService.openSession(sessionId);

      // 保存引用以供后续编辑/删除操作使用
      _sessionId = sessionId;
      _database = sessionDb;

      final events = await sessionDb.getTimelineEvents();

      if (mounted) {
        state = AsyncValue.data(events);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// 删除事件
  ///
  /// [eventId] 事件 ID
  /// [type] 事件类型
  Future<void> removeEvent(String eventId, TimelineEventType type) async {
    final db = _database;
    final sessionId = _sessionId;
    if (db == null || sessionId == null) return;

    final timelineService = TimelineService(db);
    await timelineService.deleteEvent(eventId, type);
    await loadEvents(sessionId);
  }

  /// 根据 ID 获取照片
  Future<Photo?> getPhotoById(String id) async {
    final db = _database;
    if (db == null) return null;
    return db.getPhotoById(id);
  }

  /// 根据 ID 获取视频分片
  Future<VideoChunk?> getVideoChunkById(String id) async {
    final db = _database;
    if (db == null) return null;
    return db.getVideoChunkById(id);
  }

  /// 更新照片
  Future<void> updatePhoto(Photo photo) async {
    final db = _database;
    final sessionId = _sessionId;
    if (db == null || sessionId == null) return;

    final timelineService = TimelineService(db);
    await timelineService.updatePhoto(photo);
    await loadEvents(sessionId);
  }

  /// 更新视频分片
  Future<void> updateVideoChunk(VideoChunk chunk) async {
    final db = _database;
    final sessionId = _sessionId;
    if (db == null || sessionId == null) return;

    final timelineService = TimelineService(db);
    await timelineService.updateVideoChunk(chunk);
    await loadEvents(sessionId);
  }

  /// 更新文字笔记
  Future<void> updateTextNote(TextNote note) async {
    final db = _database;
    final sessionId = _sessionId;
    if (db == null || sessionId == null) return;

    final timelineService = TimelineService(db);
    await timelineService.updateTextNote(note);
    await loadEvents(sessionId);
  }

  /// 更新书签
  Future<void> updateBookmark(Bookmark bookmark) async {
    final db = _database;
    final sessionId = _sessionId;
    if (db == null || sessionId == null) return;

    final timelineService = TimelineService(db);
    await timelineService.updateBookmark(bookmark);
    await loadEvents(sessionId);
  }
}

/// 回放时间轴事件 Provider
///
/// Author: GDNDZZK
final playbackEventsProvider =
    StateNotifierProvider<PlaybackEventsNotifier, AsyncValue<List<TimelineEvent>>>((ref) {
  return PlaybackEventsNotifier(ref);
});

/// 回放控制 Notifier
///
/// 管理音频回放的完整生命周期，包括加载、播放、暂停、跳转等操作。
/// Author: GDNDZZK
class PlaybackControlNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  PlaybackControlNotifier(this._ref) : super(const AsyncValue.data(null));

  /// 加载会话音频
  ///
  /// [sessionId] 会话 ID
  ///
  /// 从数据库加载音频分片并合并，同时加载时间轴事件。
  Future<void> loadSession(String sessionId) async {
    try {
      state = const AsyncValue.loading();

      final service = _ref.read(playbackServiceProvider);
      final storageService = await _ref.read(storageServiceProvider.future);
      final sessionDb = await storageService.openSession(sessionId);

      await service.loadSession(sessionId, sessionDb);

      // 加载时间轴事件
      await _ref.read(playbackEventsProvider.notifier).loadEvents(sessionId);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 播放
  Future<void> play() async {
    try {
      final service = _ref.read(playbackServiceProvider);
      await service.play();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      final service = _ref.read(playbackServiceProvider);
      await service.pause();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 跳转到指定时间位置
  ///
  /// [milliseconds] 目标位置（毫秒）
  Future<void> seekTo(int milliseconds) async {
    try {
      final service = _ref.read(playbackServiceProvider);
      await service.seekTo(milliseconds);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 跳转到下一个事件时间点
  Future<void> skipToNextEvent() async {
    try {
      final service = _ref.read(playbackServiceProvider);
      final eventsState = _ref.read(playbackEventsProvider);
      final events = eventsState.valueOrNull ?? [];
      await service.skipToNextEvent(events);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 跳转到上一个事件时间点
  Future<void> skipToPreviousEvent() async {
    try {
      final service = _ref.read(playbackServiceProvider);
      final eventsState = _ref.read(playbackEventsProvider);
      final events = eventsState.valueOrNull ?? [];
      await service.skipToPreviousEvent(events);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// 回放控制 Provider
///
/// Author: GDNDZZK
final playbackControlProvider =
    StateNotifierProvider<PlaybackControlNotifier, AsyncValue<void>>((ref) {
  return PlaybackControlNotifier(ref);
});
