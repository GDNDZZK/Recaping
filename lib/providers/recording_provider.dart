import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bookmark.dart';
import '../models/photo.dart';
import '../models/text_note.dart';
import '../models/timeline_event.dart';
import '../services/camera_service.dart';
import '../services/recording_service.dart';
import '../services/timeline_service.dart';
import 'session_provider.dart';

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
  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _timelineService = null;
    if (mounted) {
      state = [];
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

  RecordingControlNotifier(this._ref) : super(const AsyncValue.data(null));

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
      final sessionId = await recordingService.startSession(sessionDb);

      // 初始化时间轴服务
      final timelineService = TimelineService(sessionDb);
      timelineService.setCurrentSession(sessionId, DateTime.now());

      // 更新时间轴事件列表的 service 引用
      _ref.read(timelineEventsProvider.notifier).setTimelineService(timelineService);

      state = const AsyncValue.data(null);
      return sessionId;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 暂停录音
  ///
  /// 总时间轴继续运行，仅暂停录音。
  Future<void> pauseRecording() async {
    try {
      final recordingService = _ref.read(recordingServiceProvider);
      await recordingService.pauseRecording();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 继续录音
  Future<void> resumeRecording() async {
    try {
      final recordingService = _ref.read(recordingServiceProvider);
      await recordingService.resumeRecording();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 停止录音会话
  ///
  /// 保存最后一个音频分片，更新会话信息，清理时间轴服务。
  Future<void> stopSession() async {
    try {
      state = const AsyncValue.loading();

      final recordingService = _ref.read(recordingServiceProvider);
      final sessionId = recordingService.currentSessionId;

      // 停止录音
      await recordingService.stopSession();

      // 更新会话信息（时长等）
      if (sessionId != null) {
        try {
          final storageService = await _ref.read(storageServiceProvider.future);
          final session = await storageService.getSession(sessionId);
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

      // 清理时间轴事件
      _ref.read(timelineEventsProvider.notifier).clear();

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 拍照
  ///
  /// 调用相机服务拍照，将照片添加到时间轴。
  Future<void> takePhoto() async {
    try {
      final cameraService = _ref.read(cameraServiceProvider);
      final result = await cameraService.takePhoto();
      if (result == null) return; // 用户取消

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      final photo = await timelineService.addPhoto(
        result.data,
        width: result.width,
        height: result.height,
      );
      await timelineNotifier.addPhoto(photo);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 从相册选择照片
  ///
  /// 调用相机服务从相册选择照片，将照片添加到时间轴。
  Future<void> pickPhotoFromGallery() async {
    try {
      final cameraService = _ref.read(cameraServiceProvider);
      final result = await cameraService.pickFromGallery();
      if (result == null) return; // 用户取消

      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      final photo = await timelineService.addPhoto(
        result.data,
        width: result.width,
        height: result.height,
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
  Future<void> addTextNote(String content, {String? title}) async {
    try {
      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      final note = await timelineService.addTextNote(content, title: title);
      await timelineNotifier.addTextNote(note);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 添加书签
  ///
  /// [label] 书签标签（可选）
  /// [color] 书签颜色（可选）
  Future<void> addBookmark({String? label, String? color}) async {
    try {
      final timelineNotifier = _ref.read(timelineEventsProvider.notifier);
      final timelineService = timelineNotifier._timelineService;
      if (timelineService == null) return;

      final bookmark = await timelineService.addBookmark(
        label: label,
        color: color,
      );
      await timelineNotifier.addBookmark(bookmark);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// 录音控制 Provider
///
/// Author: GDNDZZK
final recordingControlProvider =
    StateNotifierProvider<RecordingControlNotifier, AsyncValue<void>>((ref) {
  return RecordingControlNotifier(ref);
});
