import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/database/session_database.dart';
import '../models/audio_chunk.dart';

/// 录音状态枚举
enum RecordingState {
  /// 空闲
  idle,

  /// 录音中（总时间轴运行中，录音也运行中）
  recording,

  /// 录音暂停（总时间轴运行中，录音暂停）
  paused,

  /// 已停止
  stopped,
}

/// 录音计时数据
///
/// 包含双时间轴的计时信息，用于 UI 更新。
class RecordingTick {
  /// 总时间轴已过时间（毫秒）
  final int totalElapsedMs;

  /// 录音时间轴已过时间（毫秒）
  final int audioElapsedMs;

  /// 当前录音状态
  final RecordingState state;

  /// 当前分片序号
  final int chunkIndex;

  const RecordingTick({
    required this.totalElapsedMs,
    required this.audioElapsedMs,
    required this.state,
    required this.chunkIndex,
  });

  @override
  String toString() =>
      'RecordingTick('
      'totalElapsedMs: $totalElapsedMs, '
      'audioElapsedMs: $audioElapsedMs, '
      'state: $state, '
      'chunkIndex: $chunkIndex'
      ')';
}

/// 录音服务
///
/// 管理双时间轴模型：
/// - **总时间轴**：从开始到结束的真实时间，始终递增
/// - **录音时间轴**：可在总时间轴内独立暂停/继续
///
/// 录音输出到临时文件，每 15 秒自动分段，将音频数据读取为 [Uint8List] 后存入数据库。
/// Author: GDNDZZK
class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final _uuid = const Uuid();

  // ==================== 状态 ====================

  RecordingState _state = RecordingState.idle;
  String? _currentSessionId;

  // ==================== 时间追踪 ====================

  /// 总时间轴已过时间（毫秒）
  int _totalElapsedMs = 0;

  /// 录音时间轴已过时间（毫秒），仅在录音时递增
  int _audioElapsedMs = 0;

  /// 当前录音分片开始时相对于录音时间轴的时间（毫秒）
  int _audioChunkStartMs = 0;

  /// 当前分片序号
  int _chunkIndex = 0;

  /// 当前分片录音开始时间（用于计算分片内录音时长）
  DateTime? _chunkRecordingStartTime;

  // ==================== 定时器 ====================

  Timer? _tickTimer;
  Timer? _chunkTimer;

  // ==================== 流控制器 ====================

  final _stateController = StreamController<RecordingState>.broadcast();
  final _tickController = StreamController<RecordingTick>.broadcast();

  // ==================== 数据库引用 ====================

  SessionDatabase? _sessionDb;

  // ==================== 临时文件 ====================

  /// 当前录音临时文件路径
  String? _currentChunkFilePath;

  // ==================== Getters ====================

  /// 当前录音状态
  RecordingState get state => _state;

  /// 当前会话 ID
  String? get currentSessionId => _currentSessionId;

  /// 是否正在录音
  bool get isRecording => _state == RecordingState.recording;

  /// 是否暂停中
  bool get isPaused => _state == RecordingState.paused;

  /// 是否处于活跃状态（录音中或暂停中）
  bool get isActive =>
      _state != RecordingState.idle && _state != RecordingState.stopped;

  /// 总时间轴已过时间（毫秒）
  int get totalElapsedMs => _totalElapsedMs;

  /// 录音时间轴已过时间（毫秒）
  int get audioElapsedMs => _audioElapsedMs;

  // ==================== Streams ====================

  /// 录音状态变化流
  Stream<RecordingState> get onStateChanged => _stateController.stream;

  /// 录音计时更新流（每 100ms 触发一次）
  Stream<RecordingTick> get onTick => _tickController.stream;

  // ==================== 公共方法 ====================

  /// 开始新的录音会话
  ///
  /// [sessionDb] 会话数据库实例，用于存储音频分片数据
  ///
  /// 返回新创建的会话 ID
  ///
  /// 抛出 [StateError] 如果已经在录音会话中
  /// 抛出 [Exception] 如果麦克风权限未授予
  Future<String> startSession(SessionDatabase sessionDb) async {
    if (_state != RecordingState.idle) {
      throw StateError('Already in a recording session');
    }

    // 检查麦克风权限
    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission not granted');
    }

    _sessionDb = sessionDb;
    _currentSessionId = _uuid.v4();
    _totalElapsedMs = 0;
    _audioElapsedMs = 0;
    _chunkIndex = 0;
    _audioChunkStartMs = 0;

    // 开始第一段录音
    await _startRecordingChunk();

    // 启动总时间轴计时器（每 100ms 更新一次）
    _startTickTimer();

    // 启动自动分段计时器（每 15 秒分段）
    _startChunkTimer();

    _setState(RecordingState.recording);
    return _currentSessionId!;
  }

  /// 暂停录音（总时间轴继续运行）
  Future<void> pauseRecording() async {
    if (_state != RecordingState.recording) return;

    // 停止当前分片并保存
    await _stopAndSaveCurrentChunk();
    _chunkTimer?.cancel();

    // 暂停录音器
    await _recorder.pause();

    _setState(RecordingState.paused);
  }

  /// 继续录音
  Future<void> resumeRecording() async {
    if (_state != RecordingState.paused) return;

    _audioChunkStartMs = _audioElapsedMs;

    // 恢复录音器
    await _recorder.resume();

    // 记录分片录音开始时间
    _chunkRecordingStartTime = DateTime.now();

    // 重新启动自动分段计时器
    _startChunkTimer();

    _setState(RecordingState.recording);
  }

  /// 停止会话（结束总时间轴）
  ///
  /// 保存最后一个音频分片，停止所有计时器。
  Future<void> stopSession() async {
    if (_state == RecordingState.idle) return;

    if (_state == RecordingState.recording) {
      // 保存当前正在录音的分片
      await _stopAndSaveCurrentChunk();
    }

    // 停止录音器
    await _recorder.stop();

    // 停止所有计时器
    _tickTimer?.cancel();
    _tickTimer = null;
    _chunkTimer?.cancel();
    _chunkTimer = null;

    _setState(RecordingState.stopped);
  }

  /// 释放资源
  ///
  /// 必须在不再使用服务时调用，会先停止录音会话。
  Future<void> dispose() async {
    await stopSession();
    await _stateController.close();
    await _tickController.close();
    await _recorder.dispose();
  }

  // ==================== 私有方法 ====================

  /// 更新录音状态并通知监听者
  void _setState(RecordingState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// 启动总时间轴计时器
  void _startTickTimer() {
    _tickTimer?.cancel();
    final startTime = DateTime.now();
    final audioResumeTime = DateTime.now();
    _chunkRecordingStartTime = audioResumeTime;

    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      _totalElapsedMs = now.difference(startTime).inMilliseconds;

      if (_state == RecordingState.recording && _chunkRecordingStartTime != null) {
        // 录音时间 = 之前累计的录音时间 + 当前分片内录音时间
        final chunkRecordingMs =
            now.difference(_chunkRecordingStartTime!).inMilliseconds;
        _audioElapsedMs = _audioChunkStartMs + chunkRecordingMs;
      }

      if (!_tickController.isClosed) {
        _tickController.add(
          RecordingTick(
            totalElapsedMs: _totalElapsedMs,
            audioElapsedMs: _audioElapsedMs,
            state: _state,
            chunkIndex: _chunkIndex,
          ),
        );
      }
    });
  }

  /// 启动自动分段计时器（每 15 秒分段）
  void _startChunkTimer() {
    _chunkTimer?.cancel();
    _chunkTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.audioChunkDurationMs),
      (_) async {
        if (_state != RecordingState.recording) return;
        await _rotateChunk();
      },
    );
  }

  /// 轮转分片：停止当前分片，保存数据，开始新分片
  Future<void> _rotateChunk() async {
    await _stopAndSaveCurrentChunk();
    _chunkIndex++;
    _audioChunkStartMs = _audioElapsedMs;
    await _startRecordingChunk();
  }

  /// 开始录音到新的临时文件
  Future<void> _startRecordingChunk() async {
    final tempDir = await getTemporaryDirectory();
    _currentChunkFilePath = p.join(
      tempDir.path,
      'recording_${_currentSessionId}_chunk_$_chunkIndex.m4a',
    );

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      sampleRate: AppConstants.defaultSampleRate,
      numChannels: AppConstants.defaultChannels,
      bitRate: 128000,
    );

    await _recorder.start(config, path: _currentChunkFilePath!);
    _chunkRecordingStartTime = DateTime.now();
  }

  /// 停止当前录音分片，读取音频数据并保存到数据库
  Future<void> _stopAndSaveCurrentChunk() async {
    if (_currentChunkFilePath == null) return;

    // 停止录音，获取输出文件路径
    final outputPath = await _recorder.stop();
    if (outputPath == null) return;

    final file = File(outputPath);
    if (!await file.exists()) return;

    // 读取音频数据
    final audioData = await file.readAsBytes();

    if (audioData.isEmpty) {
      // 空数据，删除临时文件
      await file.delete();
      return;
    }

    // 计算分片时间信息
    final chunkStartTime = _audioChunkStartMs;
    final chunkEndTime = _audioElapsedMs;

    // 创建 AudioChunk 并保存到数据库
    if (_sessionDb != null) {
      final chunk = AudioChunk(
        id: _uuid.v4(),
        chunkIndex: _chunkIndex,
        startTime: chunkStartTime,
        endTime: chunkEndTime,
        data: Uint8List.fromList(audioData),
        format: AppConstants.defaultAudioFormat,
        sampleRate: AppConstants.defaultSampleRate,
        channels: AppConstants.defaultChannels,
      );

      await _sessionDb!.insertAudioChunk(chunk);
    }

    // 删除临时文件
    try {
      await file.delete();
    } catch (_) {
      // 忽略临时文件删除失败
    }

    _currentChunkFilePath = null;
  }
}
