import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/database/session_database.dart';
import '../models/audio_chunk.dart';

/// 音频振幅数据
///
/// 包含当前振幅和最大振幅（dBFS 值）。
/// dBFS 值范围通常为 -60dB 到 0dB。
/// Author: GDNDZZK
class AudioAmplitude {
  /// 当前振幅（dBFS）
  final double current;

  /// 最大振幅（dBFS）
  final double max;

  const AudioAmplitude({
    required this.current,
    required this.max,
  });

  /// 将 dBFS 值转换为 0.0 ~ 1.0 的可视化高度
  ///
  /// dBFS 范围：-60dB（静音）到 0dB（最大）
  /// 返回值：0.0（静音）到 1.0（最大）
  double toNormalizedHeight() {
    // dBFS 值为负数，越接近 0 表示声音越大
    // 将 -60 ~ 0 映射到 0.0 ~ 1.0
    const minDb = -60.0;
    const maxDb = 0.0;
    
    // 使用 current 值计算
    final normalized = (current - minDb) / (maxDb - minDb);
    // 限制在 0.0 ~ 1.0 范围内
    return normalized.clamp(0.0, 1.0);
  }

  @override
  String toString() => 'AudioAmplitude(current: $current dB, max: $max dB)';
}

/// 录音状态枚举
enum RecordingState {
  /// 空闲
  idle,

  /// 录音中（总时间轴运行中，录音也运行中）
  recording,

  /// 录音暂停（总时间轴运行中，录音暂停）
  paused,

  /// 总时间轴暂停（所有操作暂停，不可添加事件）
  totalPaused,

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
/// 录音输出到临时文件，每 15 秒自动分段，将音频文件移动到会话目录的 audio/ 子目录，
/// 数据库只存储文件路径引用。
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

  /// 总时间轴的基准时间（用于计算已过时间）
  DateTime? _totalTimelineBase;

  /// 总时间轴暂停前已累计的时间（毫秒）
  int _totalElapsedBeforePause = 0;

  /// 总时间轴暂停前的录音状态（用于恢复时还原正确的录音状态）
  RecordingState? _stateBeforeTotalPause;

  // ==================== 定时器 ====================

  Timer? _tickTimer;
  Timer? _chunkTimer;

  // ==================== 流控制器 ====================

  final _stateController = StreamController<RecordingState>.broadcast();
  final _tickController = StreamController<RecordingTick>.broadcast();
  final _amplitudeController = StreamController<AudioAmplitude>.broadcast();

  // ==================== 振幅监听 ====================

  /// 振幅流订阅
  StreamSubscription<Amplitude>? _amplitudeSubscription;

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

  /// 总时间轴是否暂停
  bool get isTotalTimelinePaused => _state == RecordingState.totalPaused;

  // ==================== Streams ====================

  /// 录音状态变化流
  Stream<RecordingState> get onStateChanged => _stateController.stream;

  /// 录音计时更新流（每 100ms 触发一次）
  Stream<RecordingTick> get onTick => _tickController.stream;

  /// 音频振幅更新流
  ///
  /// 仅在录音状态下有数据，暂停或停止时无数据。
  /// 振幅数据为 dBFS 值，范围通常为 -60dB 到 0dB。
  Stream<AudioAmplitude> get onAmplitude => _amplitudeController.stream;

  // ==================== 公共方法 ====================

  /// 开始新的录音会话
  ///
  /// [sessionDb] 会话数据库实例，用于存储音频分片元数据
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
    _totalElapsedBeforePause = 0;
    _totalTimelineBase = null;
    _stateBeforeTotalPause = null;

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

    // 递增分片序号，创建新的音频分片
    _chunkIndex++;
    _audioChunkStartMs = _audioElapsedMs;

    // 开始新的录音分片
    await _startRecordingChunk();

    // 重新启动自动分段计时器
    _startChunkTimer();

    _setState(RecordingState.recording);
  }

  /// 暂停总时间轴
  ///
  /// 暂停总时间轴计时器和录音（如果正在录音）。
  /// 暂停期间不可添加任何事件。
  ///
  /// **重要**：必须先取消计时器再执行异步操作，否则在异步操作（文件 I/O）
  /// 期间计时器会继续更新 [__totalElapsedMs]，导致时间跳跃。
  Future<void> pauseTotalTimeline() async {
    if (_state != RecordingState.recording && _state != RecordingState.paused) {
      return;
    }

    // 记录总暂停前的录音状态，用于恢复时还原正确的状态
    _stateBeforeTotalPause = _state;

    // 先暂停总时间轴计时器，防止异步操作期间继续更新时间
    _tickTimer?.cancel();
    _tickTimer = null;

    // 保存当前累计的总时间
    _totalElapsedBeforePause = _totalElapsedMs;

    // 如果正在录音，先暂停录音
    if (_state == RecordingState.recording) {
      await _stopAndSaveCurrentChunk();
      _chunkTimer?.cancel();
      await _recorder.pause();
    }

    _setState(RecordingState.totalPaused);
  }

  /// 继续总时间轴
  ///
  /// 恢复总时间轴计时器。
  /// 如果总暂停前录音是活跃的，同时恢复录音；
  /// 如果总暂停前录音是暂停的，仅恢复时间轴，保持录音暂停状态。
  Future<void> resumeTotalTimeline() async {
    if (_state != RecordingState.totalPaused) return;

    // 恢复总暂停前的录音状态
    final wasRecording = _stateBeforeTotalPause == RecordingState.recording;
    _stateBeforeTotalPause = null;

    // 重置基准时间，保持时间连续性
    _totalTimelineBase = DateTime.now();

    if (wasRecording) {
      // 之前是录音中，恢复录音
      _audioChunkStartMs = _audioElapsedMs;
      await _recorder.resume();
      _chunkRecordingStartTime = DateTime.now();
      _startChunkTimer();
    }
    // 如果之前是暂停状态，不恢复录音器

    // 重启总时间轴计时器
    _startTickTimerFromPause();

    _setState(wasRecording ? RecordingState.recording : RecordingState.paused);
  }

  /// 停止会话（结束总时间轴）
  ///
  /// 保存最后一个音频分片，停止所有计时器。
  Future<void> stopSession() async {
    if (_state == RecordingState.idle) return;

    if (_state == RecordingState.recording) {
      // 保存当前正在录音的分片（内部会调用 _recorder.stop()）
      await _stopAndSaveCurrentChunk();
    } else if (_state == RecordingState.paused ||
        _state == RecordingState.totalPaused) {
      // 暂停状态下录音器已暂停，需要停止录音器
      try {
        await _recorder.stop();
      } catch (_) {
        // 录音器可能已经停止，忽略错误
      }
    }

    // 停止所有计时器
    _tickTimer?.cancel();
    _tickTimer = null;
    _chunkTimer?.cancel();
    _chunkTimer = null;

    // 重置状态为 idle，允许再次启动新会话
    _setState(RecordingState.idle);
    _currentSessionId = null;
    _sessionDb = null;
    _currentChunkFilePath = null;
    _chunkRecordingStartTime = null;
  }

  /// 释放资源
  ///
  /// 必须在不再使用服务时调用，会先停止录音会话。
  Future<void> dispose() async {
    await stopSession();
    await _stateController.close();
    await _tickController.close();
    await _amplitudeController.close();
    _stopAmplitudeListening();
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

  /// 启动总时间轴计时器（首次启动）
  void _startTickTimer() {
    _tickTimer?.cancel();
    final startTime = DateTime.now();
    _totalTimelineBase = startTime;
    _totalElapsedBeforePause = 0;
    final audioResumeTime = DateTime.now();
    _chunkRecordingStartTime = audioResumeTime;

    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      _totalElapsedMs = _totalElapsedBeforePause +
          now.difference(_totalTimelineBase!).inMilliseconds;

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

  /// 从暂停状态恢复总时间轴计时器
  void _startTickTimerFromPause() {
    _tickTimer?.cancel();
    // _totalTimelineBase 已在 resumeTotalTimeline 中设置为 DateTime.now()
    // _totalElapsedBeforePause 已在 pauseTotalTimeline 中保存

    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      _totalElapsedMs = _totalElapsedBeforePause +
          now.difference(_totalTimelineBase!).inMilliseconds;

      if (_state == RecordingState.recording && _chunkRecordingStartTime != null) {
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

    // 启动振幅监听（每 100ms 更新一次）
    _startAmplitudeListening();
  }

  /// 启动振幅监听
  ///
  /// 使用 `record` 包的 `onAmplitudeChanged` 方法获取实时振幅数据。
  /// 振幅更新频率为 100ms，与 UI 刷新频率匹配。
  void _startAmplitudeListening() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(
      (amplitude) {
        if (!_amplitudeController.isClosed) {
          _amplitudeController.add(
            AudioAmplitude(
              current: amplitude.current,
              max: amplitude.max,
            ),
          );
        }
      },
      onError: (error) {
        // 振幅监听出错时忽略，不影响录音流程
      },
    );
  }

  /// 停止振幅监听
  void _stopAmplitudeListening() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
  }

  /// 停止当前录音分片，将音频文件移动到会话目录，数据库存路径引用
  Future<void> _stopAndSaveCurrentChunk() async {
    if (_currentChunkFilePath == null) return;

    // 停止振幅监听
    _stopAmplitudeListening();

    // 停止录音，获取输出文件路径
    final outputPath = await _recorder.stop();
    if (outputPath == null) return;

    final file = File(outputPath);
    if (!await file.exists()) return;

    // 检查文件大小
    final fileSize = await file.length();
    if (fileSize == 0) {
      // 空数据，删除临时文件
      await file.delete();
      return;
    }

    // 计算分片时间信息
    final chunkStartTime = _audioChunkStartMs;
    final chunkEndTime = _audioElapsedMs;

    // 将音频文件移动到会话目录的 audio/ 子目录
    if (_sessionDb != null) {
      final relativePath = 'audio/chunk_$_chunkIndex.aac';
      final absolutePath = await _sessionDb!.resolvePath(relativePath);

      // 确保目标目录存在
      final dir = Directory(p.dirname(absolutePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 移动文件到会话目录
      await file.rename(absolutePath);

      // 创建 AudioChunk 并保存到数据库（只存路径引用）
      final chunk = AudioChunk(
        id: _uuid.v4(),
        chunkIndex: _chunkIndex,
        startTime: chunkStartTime,
        endTime: chunkEndTime,
        filePath: relativePath,
        format: AppConstants.defaultAudioFormat,
        sampleRate: AppConstants.defaultSampleRate,
        channels: AppConstants.defaultChannels,
      );

      await _sessionDb!.insertAudioChunk(chunk);
    } else {
      // 没有数据库引用，删除临时文件
      try {
        await file.delete();
      } catch (_) {
        // 忽略临时文件删除失败
      }
    }

    _currentChunkFilePath = null;
  }
}
