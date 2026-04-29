import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bookmark.dart';
import '../models/photo.dart';
import '../models/recording_segment.dart';
import '../models/text_note.dart';
import '../models/timeline_event.dart';
import '../models/video_chunk.dart';
import '../services/camera_service.dart';
import '../services/recording_service.dart';
import '../services/timeline_service.dart';
import 'session_provider.dart';

// 导出 AudioAmplitude 类型供外部使用
export '../services/recording_service.dart' show AudioAmplitude;

/// 录音服务 Provider
///
/// 提供 [RecordingService] 单例，在 Provider 销毁时自动释放资源。
/// Author: GDNDZZK
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = RecordingService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 相机服务 Provider
///
/// 提供 [CameraService] 实例。
/// Author: GDNDZZK
final cameraServiceProvider = Provider<CameraService>((ref) {
  return CameraService();
});

/// 录音状态 Provider
///
/// 监听 [RecordingService.onStateChanged] 流，自动更新录音状态。
/// Author: GDNDZZK
final recordingStateProvider = StreamProvider<RecordingState>((ref) {
  final service = ref.watch(recordingServiceProvider);
  return service.onStateChanged;
});

/// 当前会话 ID Provider
///
/// 返回当前正在录音的会话 ID，未录音时为 null。
/// Author: GDNDZZK
final currentSessionIdProvider = Provider<String?>((ref) {
  final service = ref.watch(recordingServiceProvider);
  return service.currentSessionId;
});

/// 总时间轴已过时间（毫秒）Provider
///
/// 监听 [RecordingService.onTick] 流，返回最新的总时间轴已过时间。
/// Author: GDNDZZK
final totalElapsedMsProvider = StreamProvider<int>((ref) {
  final service = ref.watch(recordingServiceProvider);
  return service.onTick.map((tick) => tick.totalElapsedMs);
});

/// 录音时间轴已过时间（毫秒）Provider
///
/// 监听 [RecordingService.onTick] 流，返回最新的录音时间轴已过时间。
/// Author: GDNDZZK
final audioElapsedMsProvider = StreamProvider<int>((ref) {
  final service = ref.watch(recordingServiceProvider);
  return service.onTick.map((tick) => tick.audioElapsedMs);
});

/// 当前分片序号 Provider
///
/// 监听 [RecordingService.onTick] 流，返回当前录音分片序号。
/// Author: GDNDZZK
final chunkIndexProvider = StreamProvider<int>((ref) {
  final service = ref.watch(recordingServiceProvider);
  return service.onTick.map((tick) => tick.chunkIndex);
});

/// 总时间轴是否暂停 Provider
///
/// 监听 [RecordingService.onStateChanged] 流，返回总时间轴是否暂停。
/// Author: GDNDZZK
final isTotalTimelinePausedProvider = Provider<bool>((ref) {
  final stateAsync = ref.watch(recordingStateProvider);
  return stateAsync.valueOrNull == RecordingState.totalPaused;
});

/// 音频振幅 Provider
///
/// 监听 [RecordingService.onAmplitude] 流，返回最新的音频振幅数据。
/// 仅在录音状态下有数据，暂停或停止时返回 null。
/// Author: GDNDZZK
final amplitudeProvider = StreamProvider<AudioAmplitude?>((ref) {
  final service = ref.watch(recordingServiceProvider);
  final stateAsync = ref.watch(recordingStateProvider);
  
  // 仅在录音状态下监听振幅
  if (stateAsync.valueOrNull != RecordingState.recording) {
    return Stream.value(null);
  }
  
  return service.onAmplitude;
});

/// 录音段列表 Provider
///
/// 管理当前录音会话的录音/暂停段列表，用于录音状态条可视化。
/// 绿色段（isRecording=true）表示录音中，红色段（isRecording=false）表示暂停间隔。
/// Author: GDNDZZK
final recordingSegmentsProvider = StateProvider<List<RecordingSegment>>((ref) => []);

/// 时间轴事件列表 Notifier
///
/// 管理当前录音会话的时间轴事件列表，提供添加/删除/刷新操作。
/// Author: GDNDZZK
class TimelineEventsNotifier extends StateNotifier<List<TimelineEvent>> {
  TimelineService? _timelineService;
  StreamSubscription<List<TimelineEvent>>? _subscription;

  TimelineEventsNotifier() : super([]);

  /// 设置时间轴服务并开始监听事件
  void setTimelineService(TimelineService service) {
    _timelineService = service;
    refresh();
  }

  /// 刷新时间轴事件列表
  Future<void> refresh() async {
    if (_timelineService == null) return;
    final events = await _timelineService!.getTimelineEvents();
    if (mounted) {
      state = events;
    }
  }

  /// 添加照片事件
  ///
  /// 通过 [TimelineService] 添加照片后自动刷新事件列表。
  Future<void> addPhoto(Photo photo) async {
    await refresh();
  }

  /// 添加文字笔记事件
  ///
  /// 通过 [TimelineService] 添加笔记后自动刷新事件列表。
  Future<void> addTextNote(TextNote note) async {
    await refresh();
  }

  /// 添加书签事件
  ///
  /// 通过 [TimelineService] 添加书签后自动刷新事件列表。
  Future<void> addBookmark(Bookmark bookmark) async {
    await refresh();
  }

  /// 添加视频事件
  ///
  /// 通过 [TimelineService] 添加视频后自动刷新事件列表。
  Future<void> addVideo(VideoChunk videoChunk) async {
    await refresh();
  }

  /// 更新文字笔记
  ///
  /// 通过 [TimelineService] 更新笔记内容后自动刷新事件列表。
  Future<void> updateTextNote(TextNote note) async {
    if (_timelineService == null) return;
    await _timelineService!.updateTextNote(note);
    await refresh();
  }

  /// 更新书签
  ///
  /// 通过 [TimelineService] 更新书签内容后自动刷新事件列表。
  Future<void> updateBookmark(Bookmark bookmark) async {
    if (_timelineService == null) return;
    await _timelineService!.updateBookmark(bookmark);
    await refresh();
  }

  /// 删除事件
  ///
  /// [id] 事件 ID
  /// [type] 事件类型
  Future<void> removeEvent(String id, TimelineEventType type) async {
    if (_timelineService == null) return;
    await _timelineService!.deleteEvent(id, type);
    await refresh();
  }

  /// 清空事件列表并释放资源
  ///
  /// 安全清理：先释放资源，再检查 mounted 后更新状态。
  void clear() {
    // 先释放资源（不依赖 mounted）
    _subscription?.cancel();
    _subscription = null;
    _timelineService = null;
    
    // 仅在 Provider 仍然有效时更新状态
    // 使用 try-catch 防止在 dispose 过程中触发断言错误
    try {
      if (mounted) {
        state = [];
      }
    } catch (_) {
      // 忽略 dispose 过程中的状态更新错误
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// 时间轴事件列表 Provider
///
/// Author: GDNDZZK
final timelineEventsProvider =
    StateNotifierProvider<TimelineEventsNotifier, List<TimelineEvent>>((ref) {
  return TimelineEventsNotifier();
});

/// 录音控制 Notifier
///
/// 管理录音会话的完整生命周期，包括开始、暂停、继续、停止录音，
/// 以及拍照、添加笔记和书签等操作。
/// Author: GDNDZZK
class RecordingControlNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  /// 上次操作时间，用于防抖
  DateTime? _lastOperationTime;

  /// 最小操作间隔（防抖时间）
  static const _minOperationInterval = Duration(milliseconds: 500);

  RecordingControlNotifier(this._ref) : super(const AsyncValue.data(null));

  /// 防抖检查
  ///
  /// 如果距离上次操作时间小于 [_minOperationInterval]，返回 false 表示应跳过本次操作。
  /// 否则更新 [_lastOperationTime] 并返回 true。
  bool _checkDebounce() {
    final now = DateTime.now();
    if (_lastOperationTime != null &&
        now.difference(_lastOperationTime!) < _minOperationInterval) {
      return false;
    }
    _lastOperationTime = now;
    return true;
  }

  /// 开始新的录音会话
  ///
  /// 创建新会话并初始化 [TimelineService]，然后开始录音。
  /// 成功后更新时间轴事件列表。
  Future<String?> startSession() async {
    try {
      state = const AsyncValue.loading();

      final recordingService = _ref.read(recordingServiceProvider);
      final storageService = await _ref.read(storageServiceProvider.future);

      // 创建新会话
      final session = await storageService.createSession();

      // 打开会话数据库
      final sessionDb = await storageService.openSession(session.sessionId);

      // 开始录音
      final sessionId = await recordingService.startSession(sessionDb, sessionId: session.sessionId);

      // 初始化时间轴服务
      final timelineService = TimelineService(sessionDb);
      timelineService.setCurrentSession(sessionId, DateTime.now());

      // 更新时间轴事件列表的 service 引用
      _ref.read(timelineEventsProvider.notifier).setTimelineService(timelineService);

      // 重置录音段列表，添加第一个录音段
      _ref.read(recordingSegmentsProvider.notifier).state = [
        const RecordingSegment(startMs: 0, isRecording: true),
      ];

      state = const AsyncValue.data(null);
      return session.title;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 暂停录音
  ///
  /// 总时间轴继续运行，仅暂停录音。
  /// 关闭当前录音段，添加暂停段。
  Future<void> pauseRecording() async {
    try {
      // 防抖：快速连续点击时跳过
      if (!_checkDebounce()) return;

      final recordingService = _ref.read(recordingServiceProvider);
      final currentMs = recordingService.totalElapsedMs;
      
      await recordingService.pauseRecording();
      
      // 更新录音段：关闭当前录音段，添加暂停段
      _updateSegmentsOnPause(currentMs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 继续录音
  ///
  /// 关闭当前暂停段，添加新的录音段。
  Future<void> resumeRecording() async {
    try {
      // 防抖：快速连续点击时跳过
      if (!_checkDebounce()) return;

      final recordingService = _ref.read(recordingServiceProvider);
      final currentMs = recordingService.totalElapsedMs;
      
      await recordingService.resumeRecording();
      
      // 更新录音段：关闭当前暂停段，添加新的录音段
      _updateSegmentsOnResume(currentMs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 暂停总时间轴
  ///
  /// 暂停总时间轴计时器和录音，暂停期间不可添加任何事件。
  /// 不影响录音段，录音段只由录音本身的暂停/恢复操作触发。
  Future<void> pauseTotalTimeline() async {
    try {
      final recordingService = _ref.read(recordingServiceProvider);
      
      await recordingService.pauseTotalTimeline();
      
      // 不更新录音段：暂停总时间轴不应改变录音段状态
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 继续总时间轴
  ///
  /// 恢复总时间轴计时器和录音。
  /// 不影响录音段和录音状态，保持录音的原始状态。
  Future<void> resumeTotalTimeline() async {
    try {
      final recordingService = _ref.read(recordingServiceProvider);
      
      await recordingService.resumeTotalTimeline();
      
      // 不更新录音段：恢复总时间轴不应改变录音段状态
      // 如果录音之前是暂停的，恢复后仍然保持暂停状态
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 停止录音会话
  ///
  /// 保存最后一个音频分片，更新会话信息，清理时间轴服务。
  /// 使用 [mounted] 检查确保 Provider 仍然有效时才更新状态。
  Future<void> stopSession() async {
    try {
      // 检查 Provider 是否仍然有效
      if (!mounted) return;
      state = const AsyncValue.loading();

      final recordingService = _ref.read(recordingServiceProvider);
      final sessionId = recordingService.currentSessionId;

      // 停止录音
      await recordingService.stopSession();

      // 检查 Provider 是否仍然有效（异步操作后）
      if (!mounted) return;

      // 更新会话信息（时长等）
      if (sessionId != null) {
        try {
          final storageService = await _ref.read(storageServiceProvider.future);
          if (!mounted) return; // 检查 Provider 是否仍然有效
          final session = await storageService.getSession(sessionId);
          if (!mounted) return; // 检查 Provider 是否仍然有效
          if (session != null) {
            await storageService.updateSession(
              session.copyWith(
                duration: recordingService.totalElapsedMs,
                audioDuration: recordingService.audioElapsedMs,
              ),
            );
          }
        } catch (_) {
          // 忽略会话更新失败，不影响停止流程
        }
      }

      // 清理时间轴事件（检查 Provider 是否仍然有效）
      if (!mounted) return;
      _ref.read(timelineEventsProvider.notifier).clear();

      // 清理录音段列表
      if (!mounted) return;
      _ref.read(recordingSegmentsProvider.notifier).state = [];

      // 刷新会话列表，确保首页能立即显示新录音
      if (!mounted) return;
      _ref.read(sessionListProvider.notifier).loadSessions();

      if (!mounted) return;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      // 错误状态更新也需要检查 mounted
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// 拍照
  ///
  /// 调用相机服务拍照，将照片添加到时间轴。
  /// 总时间轴暂停时不执行。
  /// 使用 [RecordingService.totalElapsedMs] 作为时间戳，确保与录音时间轴一致。
  Future<void> takePhoto() async {
    try {
      // 检查总时间轴是否暂停
      final recordingService = _ref.read(recordingServiceProvider);
      if (recordingService.isTotalTimelinePaused) return;

      final cameraService = _ref.read(cameraServiceProvider);
      final result = await cameraService.takePhoto();
      if (result == null) return; // 用户取消

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      // 使用 totalElapsedMs 作为时间戳，确保与录音时间轴一致
      final timestamp = recordingService.totalElapsedMs;
      final photo = await timelineService.addPhoto(
        result.data,
        width: result.width,
        height: result.height,
        timestamp: timestamp,
      );
      await timelineNotifier.addPhoto(photo);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 从相册选择照片
  ///
  /// 调用相机服务从相册选择照片，将照片添加到时间轴。
  /// 总时间轴暂停时不执行。
  /// 使用 [RecordingService.totalElapsedMs] 作为时间戳，确保与录音时间轴一致。
  Future<void> pickPhotoFromGallery() async {
    try {
      // 检查总时间轴是否暂停
      final recordingService = _ref.read(recordingServiceProvider);
      if (recordingService.isTotalTimelinePaused) return;

      final cameraService = _ref.read(cameraServiceProvider);
      final result = await cameraService.pickFromGallery();
      if (result == null) return; // 用户取消

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      // 使用 totalElapsedMs 作为时间戳，确保与录音时间轴一致
      final timestamp = recordingService.totalElapsedMs;
      final photo = await timelineService.addPhoto(
        result.data,
        width: result.width,
        height: result.height,
        timestamp: timestamp,
      );
      await timelineNotifier.addPhoto(photo);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 添加文字笔记
  ///
  /// [content] 笔记内容
  /// [title] 笔记标题（可选）
  /// 总时间轴暂停时不执行。
  /// 使用 [RecordingService.totalElapsedMs] 作为时间戳，确保与录音时间轴一致。
  Future<void> addTextNote(String content, {String? title}) async {
    try {
      // 检查总时间轴是否暂停
      final recordingService = _ref.read(recordingServiceProvider);
      if (recordingService.isTotalTimelinePaused) return;

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      // 使用 totalElapsedMs 作为时间戳，确保与录音时间轴一致
      final timestamp = recordingService.totalElapsedMs;
      final note = await timelineService.addTextNote(content, title: title, timestamp: timestamp);
      await timelineNotifier.addTextNote(note);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 添加书签
  ///
  /// [label] 书签标签（可选）
  /// [color] 书签颜色（可选）
  /// 总时间轴暂停时不执行。
  /// 使用 [RecordingService.totalElapsedMs] 作为时间戳，确保与录音时间轴一致。
  Future<void> addBookmark({String? label, String? color}) async {
    try {
      // 检查总时间轴是否暂停
      final recordingService = _ref.read(recordingServiceProvider);
      if (recordingService.isTotalTimelinePaused) return;

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      // 使用 totalElapsedMs 作为时间戳，确保与录音时间轴一致
      final timestamp = recordingService.totalElapsedMs;
      final bookmark = await timelineService.addBookmark(
        label: label,
        color: color,
        timestamp: timestamp,
      );
      await timelineNotifier.addBookmark(bookmark);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 录制短视频
  ///
  /// 调用相机服务录制短视频，将视频添加到时间轴。
  /// 总时间轴暂停时不执行。
  /// 使用 [RecordingService.totalElapsedMs] 作为时间戳，确保与录音时间轴一致。
  Future<void> recordVideo() async {
    try {
      // 检查总时间轴是否暂停
      final recordingService = _ref.read(recordingServiceProvider);
      if (recordingService.isTotalTimelinePaused) return;

      final cameraService = _ref.read(cameraServiceProvider);
      final result = await cameraService.recordVideo();
      if (result == null) return; // 用户取消

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      // 使用 totalElapsedMs 作为时间戳，确保与录音时间轴一致
      final timestamp = recordingService.totalElapsedMs;
      final videoChunk = await timelineService.addVideo(result.data, timestamp: timestamp);
      await timelineNotifier.addVideo(videoChunk);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 暂停录音时更新录音段
  ///
  /// 关闭当前录音段（设置 endMs），添加暂停段。
  void _updateSegmentsOnPause(int currentMs) {
    final segments = _ref.read(recordingSegmentsProvider);
    if (segments.isEmpty) return;

    final updatedSegments = List<RecordingSegment>.from(segments);
    // 关闭最后一个录音段
    final lastSegment = updatedSegments.last;
    updatedSegments[updatedSegments.length - 1] = lastSegment.copyWith(
      endMs: currentMs,
    );
    // 添加暂停段
    updatedSegments.add(RecordingSegment(
      startMs: currentMs,
      isRecording: false,
    ));

    _ref.read(recordingSegmentsProvider.notifier).state = updatedSegments;
  }

  /// 继续录音时更新录音段
  ///
  /// 关闭当前暂停段（设置 endMs），添加新的录音段。
  void _updateSegmentsOnResume(int currentMs) {
    final segments = _ref.read(recordingSegmentsProvider);
    if (segments.isEmpty) return;

    final updatedSegments = List<RecordingSegment>.from(segments);
    // 关闭最后一个暂停段
    final lastSegment = updatedSegments.last;
    updatedSegments[updatedSegments.length - 1] = lastSegment.copyWith(
      endMs: currentMs,
    );
    // 添加新的录音段
    updatedSegments.add(RecordingSegment(
      startMs: currentMs,
      isRecording: true,
    ));

    _ref.read(recordingSegmentsProvider.notifier).state = updatedSegments;
  }

}

/// 录音控制 Provider
///
/// Author: GDNDZZK
final recordingControlProvider =
    StateNotifierProvider<RecordingControlNotifier, AsyncValue<void>>((ref) {
  return RecordingControlNotifier(ref);
});
