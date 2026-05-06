import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/database/session_database.dart';
import '../models/audio_chunk.dart';
import '../models/timeline_event.dart';

/// 播放状态枚举
enum PlaybackState {
  /// 空闲
  idle,

  /// 加载中
  loading,

  /// 播放中
  playing,

  /// 暂停
  paused,

  /// 错误
  error,
}

/// 音频回放服务
///
/// 使用 Stopwatch + Timer 驱动总时间轴前进，根据当前总时间轴位置判断
/// 落在哪个录音 chunk（或静音区间），独立加载并播放对应的单个 chunk 文件。
/// Author: GDNDZZK
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  // ==================== 总时间轴定时器 ====================

  Timer? _timelineTimer;
  final Stopwatch _stopwatch = Stopwatch();

  /// 恢复/跳转前已过的总时间轴时间（毫秒）
  int _elapsedBeforeResume = 0;

  // ==================== 总时间轴状态 ====================

  /// 当前总时间轴位置（毫秒）
  int _currentTotalMs = 0;

  /// 总时间轴时长（毫秒）= session.duration
  int _totalDurationMs = 0;

  /// 播放速度
  double _speed = 1.0;

  /// 播放状态
  PlaybackState _state = PlaybackState.idle;

  // ==================== 音频 chunks ====================

  /// 按 totalStartTime 排序的音频分片列表
  List<AudioChunk> _chunks = [];

  /// 当前活跃的 chunk 索引（-1 表示静音区间）
  int _activeChunkIndex = -1;

  // ==================== Session 信息 ====================

  String? _currentSessionId;
  SessionDatabase? _sessionDb;

  // ==================== 流控制器 ====================

  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  /// 是否已释放资源
  bool _isDisposed = false;

  // ==================== Getters ====================

  /// 当前播放状态
  PlaybackState get state => _state;

  /// 当前会话 ID
  String? get currentSessionId => _currentSessionId;

  /// 总时长
  Duration get duration => Duration(milliseconds: _totalDurationMs);

  /// 当前播放位置（总时间轴位置）
  Duration get position => Duration(milliseconds: _currentTotalMs);

  /// 是否正在播放
  bool get isPlaying => _state == PlaybackState.playing;

  /// 已加载的音频分片列表（按总时间轴排序）
  List<AudioChunk> get chunks => List.unmodifiable(_chunks);

  // ==================== Streams ====================

  /// 播放状态变化流
  Stream<PlaybackState> get onStateChanged => _stateController.stream;

  /// 播放位置变化流
  Stream<Duration> get onPositionChanged => _positionController.stream;

  // ==================== 公共方法 ====================

  /// 加载会话音频
  ///
  /// 从数据库加载会话元信息和所有 [AudioChunk]，按总时间轴排序。
  /// 兼容旧数据：如果 chunk 没有 totalStartTime，退回到使用 startTime。
  Future<void> loadSession(
    String sessionId,
    SessionDatabase db,
  ) async {
    _setState(PlaybackState.loading);
    _currentSessionId = sessionId;
    _sessionDb = db;

    try {
      // 加载会话元信息获取总时长
      final session = await db.getSessionInfo();
      _totalDurationMs = session?.duration ?? 0;

      // 从数据库加载所有音频分片的元数据
      final allChunks = await db.getAudioChunks();

      if (allChunks.isEmpty) {
        _currentTotalMs = 0;
        _activeChunkIndex = -1;
        _setState(PlaybackState.idle);
        return;
      }

      // 过滤并排序：优先使用 totalStartTime
      final hasTotalTime = allChunks.any(
        (c) => c.totalStartTime > 0 || c.totalEndTime > 0,
      );

      if (hasTotalTime) {
        _chunks = allChunks
            .where((c) => c.totalStartTime > 0 || c.totalEndTime > 0)
            .toList();
        _chunks.sort((a, b) => a.totalStartTime.compareTo(b.totalStartTime));
      } else {
        // 兼容旧数据：退回到 startTime
        _chunks = allChunks.toList();
        _chunks.sort((a, b) => a.startTime.compareTo(b.startTime));
      }

      // 如果总时长为 0，尝试从 chunks 推算
      if (_totalDurationMs <= 0 && _chunks.isNotEmpty) {
        if (hasTotalTime) {
          _totalDurationMs = _chunks.last.totalEndTime;
        } else {
          _totalDurationMs = _chunks.last.endTime;
        }
      }

      _currentTotalMs = 0;
      _activeChunkIndex = -1;

      _setState(PlaybackState.paused);
    } catch (e) {
      _setState(PlaybackState.error);
      throw Exception('Failed to load session audio: $e');
    }
  }

  /// 播放
  Future<void> play() async {
    if (_state == PlaybackState.playing) return;
    if (_currentSessionId == null) return;

    _setState(PlaybackState.playing);

    _elapsedBeforeResume = _currentTotalMs;
    _stopwatch.reset();
    _stopwatch.start();

    // 立即处理当前位置
    await _handleTimelinePosition();

    // 启动定时器，每 50ms 更新一次
    _timelineTimer?.cancel();
    _timelineTimer = Timer.periodic(const Duration(milliseconds: 50), _onTick);
  }

  /// 暂停
  Future<void> pause() async {
    if (_state != PlaybackState.playing) return;

    _stopwatch.stop();
    _timelineTimer?.cancel();
    _timelineTimer = null;

    // 暂停音频播放
    try {
      await _player.pause();
    } catch (_) {
      // 播放器可能未初始化
    }

    _setState(PlaybackState.paused);
  }

  /// 跳转到指定时间位置
  ///
  /// [milliseconds] 目标位置（毫秒）
  Future<void> seekTo(int milliseconds) async {
    _currentTotalMs = milliseconds.clamp(0, _totalDurationMs);

    if (_state == PlaybackState.playing) {
      _elapsedBeforeResume = _currentTotalMs;
      _stopwatch.reset();
    }

    _emitPosition(Duration(milliseconds: _currentTotalMs));

    // 处理新位置
    await _handleTimelinePosition();
  }

  /// 跳转到下一个事件时间点
  ///
  /// [events] 时间轴事件列表（需按时间戳排序）
  /// [toleranceMs] 容差（毫秒），当前播放位置在事件时间点之后且在容差范围内时跳到下一个
  Future<void> skipToNextEvent(List<TimelineEvent> events) async {
    if (events.isEmpty) return;

    const tolerance = 500; // 500ms 容差

    // 找到当前播放位置之后的第一个事件
    for (final event in events) {
      if (event.timestamp > _currentTotalMs + tolerance) {
        await seekTo(event.timestamp);
        return;
      }
    }

    // 如果没有下一个事件，跳到末尾
    await seekTo(_totalDurationMs);
  }

  /// 跳转到上一个事件时间点
  ///
  /// [events] 时间轴事件列表（需按时间戳排序）
  Future<void> skipToPreviousEvent(List<TimelineEvent> events) async {
    if (events.isEmpty) return;

    // 找到当前播放位置之前的最后一个事件
    TimelineEvent? previousEvent;
    for (final event in events) {
      if (event.timestamp < _currentTotalMs - 500) {
        previousEvent = event;
      } else {
        break;
      }
    }

    if (previousEvent != null) {
      await seekTo(previousEvent.timestamp);
    } else {
      // 如果没有上一个事件，跳到开头
      await seekTo(0);
    }
  }

  /// 设置播放速度
  ///
  /// [speed] 播放速度（1.0 为正常速度）
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_state == PlaybackState.playing) {
      _elapsedBeforeResume = _currentTotalMs;
      _stopwatch.reset();
    }
    try {
      await _player.setSpeed(speed);
    } catch (_) {
      // 播放器可能未初始化
    }
  }

  /// 释放资源
  ///
  /// 必须在不再使用服务时调用。幂等操作，可安全多次调用。
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _stopwatch.stop();
    _timelineTimer?.cancel();
    _timelineTimer = null;
    await _player.dispose();

    // 关闭 stream controllers，防止 dispose 后继续发射事件
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
    if (!_positionController.isClosed) {
      await _positionController.close();
    }
  }

  // ==================== 私有方法 ====================

  /// 定时器回调
  void _onTick(Timer timer) {
    if (_isDisposed) return;

    _currentTotalMs =
        _elapsedBeforeResume + (_stopwatch.elapsedMilliseconds * _speed).toInt();

    // 检查是否播放结束
    if (_currentTotalMs >= _totalDurationMs) {
      _currentTotalMs = _totalDurationMs;
      _stopPlayback();
      return;
    }

    // 处理当前位置
    _handleTimelinePosition();

    // 通知位置更新
    _emitPosition(Duration(milliseconds: _currentTotalMs));
  }

  /// 处理当前时间轴位置
  ///
  /// 判断当前时间落在哪个 chunk（或静音区间），必要时切换 chunk。
  Future<void> _handleTimelinePosition() async {
    final chunkIndex = _findChunkAtTotalTime(_currentTotalMs);

    if (chunkIndex != _activeChunkIndex) {
      await _transitionToChunk(chunkIndex);
    }

    // 如果在音频 chunk 内且正在播放，同步播放位置
    if (_activeChunkIndex >= 0 && _state == PlaybackState.playing) {
      final chunk = _chunks[_activeChunkIndex];
      final hasTotalTime = chunk.totalStartTime > 0 || chunk.totalEndTime > 0;
      final chunkStart = hasTotalTime ? chunk.totalStartTime : chunk.startTime;
      final audioMs = _currentTotalMs - chunkStart;
      final expectedAudioPos = Duration(milliseconds: audioMs);

      try {
        final actualAudioPos = _player.position;
        // 如果偏差超过 200ms，校正位置
        if ((expectedAudioPos - actualAudioPos).abs() >
            const Duration(milliseconds: 200)) {
          await _player.seek(expectedAudioPos);
        }
      } catch (_) {
        // 播放器可能未就绪
      }
    }
  }

  /// 切换到指定 chunk
  Future<void> _transitionToChunk(int newIndex) async {
    if (newIndex == _activeChunkIndex) return;

    if (newIndex < 0) {
      // 进入静音区间 → 暂停音频
      try {
        await _player.pause();
      } catch (_) {
        // 播放器可能未初始化
      }
    } else {
      // 进入音频 chunk → 加载并播放
      final chunk = _chunks[newIndex];
      await _loadAndPlayChunk(chunk);
    }

    _activeChunkIndex = newIndex;
  }

  /// 加载并播放单个 chunk
  Future<void> _loadAndPlayChunk(AudioChunk chunk) async {
    try {
      // 构建文件绝对路径
      final filePath = await _getChunkFilePath(chunk);
      final file = File(filePath);

      if (!await file.exists()) {
        // 文件不存在，当作静音处理
        return;
      }

      // 计算在 chunk 内的偏移
      final hasTotalTime = chunk.totalStartTime > 0 || chunk.totalEndTime > 0;
      final chunkStart = hasTotalTime ? chunk.totalStartTime : chunk.startTime;
      final offsetInChunk = _currentTotalMs - chunkStart;

      // 加载 chunk 文件
      await _player.setFilePath(filePath);
      await _player.setSpeed(_speed);

      // seek 到正确位置
      if (offsetInChunk > 0) {
        await _player.seek(Duration(milliseconds: offsetInChunk));
      }

      // 如果正在播放，开始播放
      if (_state == PlaybackState.playing) {
        await _player.play();
      }
    } catch (e) {
      // 加载失败，当作静音处理
      debugPrint('Failed to load chunk: $e');
    }
  }

  /// 获取 chunk 文件的绝对路径
  Future<String> _getChunkFilePath(AudioChunk chunk) async {
    if (_sessionDb != null) {
      return _sessionDb!.resolvePath(chunk.filePath);
    }
    // 回退：手动构建路径
    final directory = await getApplicationDocumentsDirectory();
    return p.join(
      directory.path,
      'sessions',
      chunk.filePath,
    );
  }

  /// 查找指定总时间轴位置所在的 chunk
  ///
  /// 返回 chunk 索引，-1 表示静音区间。
  int _findChunkAtTotalTime(int totalMs) {
    for (int i = 0; i < _chunks.length; i++) {
      final chunk = _chunks[i];
      final hasTotalTime =
          chunk.totalStartTime > 0 || chunk.totalEndTime > 0;
      final start = hasTotalTime ? chunk.totalStartTime : chunk.startTime;
      final end = hasTotalTime ? chunk.totalEndTime : chunk.endTime;
      if (totalMs >= start && totalMs < end) {
        return i;
      }
    }
    return -1; // 静音区间
  }

  /// 停止播放（播放到末尾时调用）
  void _stopPlayback() {
    _stopwatch.stop();
    _timelineTimer?.cancel();
    _timelineTimer = null;
    try {
      _player.pause();
    } catch (_) {
      // 播放器可能未初始化
    }

    _emitPosition(Duration(milliseconds: _currentTotalMs));
    _setState(PlaybackState.idle);
  }

  /// 更新播放状态
  void _setState(PlaybackState newState) {
    _state = newState;
    if (!_isDisposed && !_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// 安全发射位置事件
  void _emitPosition(Duration position) {
    if (!_isDisposed && !_positionController.isClosed) {
      _positionController.add(position);
    }
  }
}
