import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/database/session_database.dart';
import '../core/utils/thumbnail_util.dart';
import '../models/bookmark.dart';
import '../models/photo.dart';
import '../models/text_note.dart';
import '../models/timeline_event.dart';
import '../models/video_chunk.dart';

/// 时间轴服务
///
/// 管理时间轴上的所有事件（拍照、笔记、书签等）。
/// 需要关联到当前活跃的录音会话，所有事件使用相对于会话开始时间的毫秒偏移量。
/// Author: GDNDZZK
class TimelineService {
  final SessionDatabase _db;
  final _uuid = const Uuid();

  /// 当前关联的会话 ID
  String? _currentSessionId;

  /// 会话开始时间，用于计算时间戳偏移
  DateTime? _sessionStartTime;

  TimelineService(this._db);

  /// 设置当前会话信息
  ///
  /// 必须在添加任何事件之前调用，用于计算事件的时间戳偏移。
  void setCurrentSession(String sessionId, DateTime startTime) {
    _currentSessionId = sessionId;
    _sessionStartTime = startTime;
  }

  /// 获取当前会话 ID
  String? get currentSessionId => _currentSessionId;

  /// 计算当前相对于会话开始时间的毫秒偏移
  int get _currentTimestamp {
    if (_sessionStartTime == null) {
      throw StateError('Session not started. Call setCurrentSession first.');
    }
    return DateTime.now().difference(_sessionStartTime!).inMilliseconds;
  }

  // ==================== 照片操作 ====================

  /// 添加照片事件
  ///
  /// [imageData] 原始图片数据
  /// [width] 图片宽度（像素）
  /// [height] 图片高度（像素）
  ///
  /// 自动生成缩略图并存入数据库。
  Future<Photo> addPhoto(
    Uint8List imageData, {
    int? width,
    int? height,
  }) async {
    _ensureSessionActive();

    final timestamp = _currentTimestamp;

    // 生成缩略图
    final thumbnail = await ThumbnailUtil.generate(
      imageData,
      maxSize: AppConstants.thumbnailMaxSize,
    );

    final photo = Photo(
      id: _uuid.v4(),
      timestamp: timestamp,
      data: imageData,
      thumbnail: thumbnail,
      format: AppConstants.defaultPhotoFormat,
      width: width ?? 0,
      height: height ?? 0,
    );

    await _db.insertPhoto(photo);
    return photo;
  }

  // ==================== 视频操作 ====================

  /// 添加视频事件
  ///
  /// [videoData] 完整视频数据
  /// [format] 视频格式（默认 mp4）
  ///
  /// 由于 Flutter 中无法精确分割视频流为 5 秒段，
  /// 简化处理：将整个视频作为一个 VideoChunk 存储（chunk_index=0）。
  /// 后续可以优化为真正的分段。
  Future<VideoChunk> addVideo(
    Uint8List videoData, {
    String format = 'mp4',
  }) async {
    _ensureSessionActive();

    final timestamp = _currentTimestamp;
    final videoId = _uuid.v4();

    final chunk = VideoChunk(
      id: _uuid.v4(),
      videoId: videoId,
      chunkIndex: 0,
      startTime: timestamp,
      endTime: timestamp + AppConstants.videoChunkDurationMs,
      data: videoData,
      format: format,
      thumbnail: null, // 视频缩略图生成较复杂，暂不实现
    );

    await _db.insertVideoChunk(chunk);
    return chunk;
  }

  // ==================== 文字笔记操作 ====================

  /// 添加文字笔记
  ///
  /// [content] 笔记内容
  /// [title] 笔记标题（可选）
  Future<TextNote> addTextNote(String content, {String? title}) async {
    _ensureSessionActive();

    final timestamp = _currentTimestamp;

    final note = TextNote(
      id: _uuid.v4(),
      timestamp: timestamp,
      title: title,
      content: content,
      createdAt: DateTime.now(),
    );

    await _db.insertTextNote(note);
    return note;
  }

  /// 更新文字笔记
  Future<void> updateTextNote(TextNote note) async {
    await _db.updateTextNote(note);
  }

  // ==================== 书签操作 ====================

  /// 添加书签
  ///
  /// [label] 书签标签（可选）
  /// [color] 书签颜色（十六进制，如 #FF6B6B）
  Future<Bookmark> addBookmark({
    String? label,
    String? color,
  }) async {
    _ensureSessionActive();

    final timestamp = _currentTimestamp;

    final bookmark = Bookmark(
      id: _uuid.v4(),
      timestamp: timestamp,
      label: label,
      color: color ?? AppConstants.defaultBookmarkColor,
      createdAt: DateTime.now(),
    );

    await _db.insertBookmark(bookmark);
    return bookmark;
  }

  /// 更新书签
  Future<void> updateBookmark(Bookmark bookmark) async {
    await _db.updateBookmark(bookmark);
  }

  // ==================== 查询操作 ====================

  /// 获取所有时间轴事件（按时间戳排序）
  Future<List<TimelineEvent>> getTimelineEvents() async {
    return _db.getTimelineEvents();
  }

  /// 获取指定时间范围内的事件
  ///
  /// [startMs] 起始时间（相对于会话开始的毫秒偏移）
  /// [endMs] 结束时间（相对于会话开始的毫秒偏移）
  Future<List<TimelineEvent>> getEventsByTimeRange(
    int startMs,
    int endMs,
  ) async {
    return _db.getTimelineEventsByTimeRange(startMs, endMs);
  }

  // ==================== 删除操作 ====================

  /// 删除事件
  ///
  /// [eventId] 事件 ID
  /// [type] 事件类型，用于确定从哪个表删除
  Future<void> deleteEvent(String eventId, TimelineEventType type) async {
    switch (type) {
      case TimelineEventType.photo:
        await _db.deletePhoto(eventId);
      case TimelineEventType.video:
        // 视频删除需要通过 videoId，这里按单个分片 ID 删除
        await _db.deleteVideoChunk(eventId);
      case TimelineEventType.textNote:
        await _db.deleteTextNote(eventId);
      case TimelineEventType.bookmark:
        await _db.deleteBookmark(eventId);
      case TimelineEventType.audio:
        // 录音区间事件不支持单独删除（由录音服务管理）
        break;
    }
  }

  // ==================== 私有方法 ====================

  /// 确保会话已激活
  void _ensureSessionActive() {
    if (_currentSessionId == null || _sessionStartTime == null) {
      throw StateError(
        'No active session. Call setCurrentSession before adding events.',
      );
    }
  }
}
