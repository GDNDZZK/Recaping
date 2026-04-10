import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
/// 从文件系统读取所有音频分片，合并后使用 [AudioPlayer] 播放。
/// 支持播放/暂停/跳转/变速等操作。
/// Author: GDNDZZK
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  // ==================== 状态 ====================

  PlaybackState _state = PlaybackState.idle;
  String? _currentSessionId;
  List<AudioChunk> _chunks = [];

  // ==================== 流控制器 ====================

  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  // ==================== 订阅 ====================

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  // ==================== Getters ====================

  /// 当前播放状态
  PlaybackState get state => _state;

  /// 当前会话 ID
  String? get currentSessionId => _currentSessionId;

  /// 总时长
  Duration get duration => _player.duration ?? Duration.zero;

  /// 当前播放位置
  Duration get position => _player.position;

  /// 是否正在播放
  bool get isPlaying => _state == PlaybackState.playing;

  // ==================== Streams ====================

  /// 播放状态变化流
  Stream<PlaybackState> get onStateChanged => _stateController.stream;

  /// 播放位置变化流
  Stream<Duration> get onPositionChanged => _positionController.stream;

  // ==================== 公共方法 ====================

  /// 加载会话音频
  ///
  /// 从数据库加载所有 [AudioChunk] 的路径引用，从文件系统读取音频数据，
  /// 合并为一个临时文件后加载到播放器。
  Future<void> loadSession(
    String sessionId,
    SessionDatabase db,
  ) async {
    _setState(PlaybackState.loading);
    _currentSessionId = sessionId;

    try {
      // 从数据库加载所有音频分片的元数据
      _chunks = await db.getAudioChunks();

      if (_chunks.isEmpty) {
        _setState(PlaybackState.idle);
        return;
      }

      // 从文件系统读取所有分片数据并合并
      final mergedData = await _mergeChunks(_chunks, db);

      // 写入临时文件
      final tempFile = await _writeTempAudioFile(sessionId, mergedData);

      // 设置播放器监听
      _setupPlayerListeners();

      // 加载音频文件
      await _player.setFilePath(tempFile.path);

      _setState(PlaybackState.paused);
    } catch (e) {
      _setState(PlaybackState.error);
      throw Exception('Failed to load session audio: $e');
    }
  }

  /// 播放
  Future<void> play() async {
    if (_state == PlaybackState.paused || _state == PlaybackState.idle) {
      await _player.play();
      _setState(PlaybackState.playing);
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_state == PlaybackState.playing) {
      await _player.pause();
      _setState(PlaybackState.paused);
    }
  }

  /// 跳转到指定时间位置
  ///
  /// [milliseconds] 目标位置（毫秒）
  Future<void> seekTo(int milliseconds) async {
    await _player.seek(Duration(milliseconds: milliseconds));
  }

  /// 跳转到下一个事件时间点
  ///
  /// [events] 时间轴事件列表（需按时间戳排序）
  /// [toleranceMs] 容差（毫秒），当前播放位置在事件时间点之后且在容差范围内时跳到下一个
  Future<void> skipToNextEvent(List<TimelineEvent> events) async {
    if (events.isEmpty) return;

    final currentMs = _player.position.inMilliseconds;
    const tolerance = 500; // 500ms 容差

    // 找到当前播放位置之后的第一个事件
    for (final event in events) {
      if (event.timestamp > currentMs + tolerance) {
        await seekTo(event.timestamp);
        return;
      }
    }

    // 如果没有下一个事件，跳到末尾
    await _player.seek(_player.duration);
  }

  /// 跳转到上一个事件时间点
  ///
  /// [events] 时间轴事件列表（需按时间戳排序）
  Future<void> skipToPreviousEvent(List<TimelineEvent> events) async {
    if (events.isEmpty) return;

    final currentMs = _player.position.inMilliseconds;

    // 找到当前播放位置之前的最后一个事件
    TimelineEvent? previousEvent;
    for (final event in events) {
      if (event.timestamp < currentMs - 500) {
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
    await _player.setSpeed(speed);
  }

  /// 释放资源
  ///
  /// 必须在不再使用服务时调用。
  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    await _player.dispose();
    await _stateController.close();
    await _positionController.close();
    await _cleanupTempFiles();
  }

  // ==================== 私有方法 ====================

  /// 更新播放状态
  void _setState(PlaybackState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// 设置播放器监听
  void _setupPlayerListeners() {
    // 监听播放位置变化
    _positionSubscription?.cancel();
    _positionSubscription = _player.positionStream.listen((position) {
      if (!_positionController.isClosed) {
        _positionController.add(position);
      }
    });

    // 监听播放器状态变化
    _playerStateSubscription?.cancel();
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _setState(PlaybackState.idle);
      }
    });
  }

  /// 从文件系统读取所有音频分片数据并合并
  Future<List<int>> _mergeChunks(
    List<AudioChunk> chunks,
    SessionDatabase db,
  ) async {
    final mergedData = <int>[];
    for (final chunk in chunks) {
      final absPath = await db.resolvePath(chunk.filePath);
      final file = File(absPath);
      if (await file.exists()) {
        final data = await file.readAsBytes();
        mergedData.addAll(data);
      }
    }
    return mergedData;
  }

  /// 将音频数据写入临时文件
  Future<File> _writeTempAudioFile(
    String sessionId,
    List<int> audioData,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = p.join(tempDir.path, 'playback_$sessionId.m4a');
    final file = File(filePath);
    await file.writeAsBytes(audioData, flush: true);
    return file;
  }

  /// 清理临时播放文件
  Future<void> _cleanupTempFiles() async {
    if (_currentSessionId != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final filePath = p.join(
          tempDir.path,
          'playback_$_currentSessionId.m4a',
        );
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 忽略临时文件清理失败
      }
    }
  }
}
