import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format_util.dart';
import '../../providers/playback_provider.dart';
import '../../services/audio_playback_service.dart';

/// 可复用的音频播放控制栏组件
///
/// 包含进度条、时间显示、播放控制按钮和速度切换功能。
/// Author: GDNDZZK
class AudioPlayerControls extends ConsumerStatefulWidget {
  /// 进度条颜色
  final Color? accentColor;

  const AudioPlayerControls({
    super.key,
    this.accentColor,
  });

  @override
  ConsumerState<AudioPlayerControls> createState() => _AudioPlayerControlsState();
}

class _AudioPlayerControlsState extends ConsumerState<AudioPlayerControls> {
  /// 支持的播放速度列表
  static const List<double> _speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时位置（毫秒）
  double _draggingValue = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accentColor = Color(0xFF6B6BFF);
    final effectiveAccentColor = widget.accentColor ?? accentColor;

    // 监听播放状态
    final playbackStateAsync = ref.watch(playbackStateProvider);
    final playbackState = playbackStateAsync.valueOrNull ?? PlaybackState.idle;

    // 监听播放位置
    final positionAsync = ref.watch(playbackPositionProvider);
    final position = positionAsync.valueOrNull ?? Duration.zero;

    // 监听总时长
    final duration = ref.watch(playbackDurationProvider);

    // 监听播放速度
    final speed = ref.watch(playbackSpeedProvider);

    // 当前显示的位置
    final displayPosition = _isDragging
        ? Duration(milliseconds: _draggingValue.toInt())
        : position;
    final totalMs = duration.inMilliseconds.toDouble();
    final currentMs = displayPosition.inMilliseconds.toDouble();
    final progressValue = totalMs > 0 ? currentMs.clamp(0.0, totalMs) : 0.0;

    final isPlaying = playbackState == PlaybackState.playing;
    final isLoading = playbackState == PlaybackState.loading;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条 + 时间显示
              _buildProgressBar(
                theme,
                colorScheme,
                effectiveAccentColor,
                progressValue,
                totalMs,
                displayPosition,
                duration,
              ),
              const SizedBox(height: 4),
              // 控制按钮行
              _buildControlButtons(
                colorScheme,
                effectiveAccentColor,
                isPlaying,
                isLoading,
                speed,
                playbackState,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建进度条和时间显示
  Widget _buildProgressBar(
    ThemeData theme,
    ColorScheme colorScheme,
    Color accentColor,
    double progressValue,
    double totalMs,
    Duration displayPosition,
    Duration duration,
  ) {
    return Row(
      children: [
        // 当前时间
        SizedBox(
          width: 48,
          child: Text(
            _formatPosition(displayPosition),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        // 进度条
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: accentColor,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: progressValue,
              min: 0,
              max: totalMs > 0 ? totalMs : 1.0,
              onChangeStart: (value) {
                setState(() {
                  _isDragging = true;
                  _draggingValue = value;
                });
              },
              onChanged: (value) {
                setState(() {
                  _draggingValue = value;
                });
              },
              onChangeEnd: (value) {
                setState(() {
                  _isDragging = false;
                });
                ref.read(playbackControlProvider.notifier).seekTo(value.toInt());
              },
            ),
          ),
        ),
        // 总时长
        SizedBox(
          width: 48,
          child: Text(
            _formatPosition(duration),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// 构建控制按钮行
  Widget _buildControlButtons(
    ColorScheme colorScheme,
    Color accentColor,
    bool isPlaying,
    bool isLoading,
    double speed,
    PlaybackState playbackState,
  ) {
    final isIdle = playbackState == PlaybackState.idle;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一个事件按钮
        IconButton(
          onPressed: isIdle
              ? null
              : () => ref.read(playbackControlProvider.notifier).skipToPreviousEvent(),
          icon: Icon(
            Icons.skip_previous,
            color: isIdle
                ? colorScheme.onSurface.withValues(alpha: 0.3)
                : colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          iconSize: 24,
          tooltip: '上一个事件',
        ),

        // 快退 15 秒
        IconButton(
          onPressed: isIdle
              ? null
              : _skipBackward,
          icon: Icon(
            Icons.history,
            color: isIdle
                ? colorScheme.onSurface.withValues(alpha: 0.3)
                : colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          iconSize: 28,
          tooltip: '快退15秒',
        ),

        const SizedBox(width: 8),

        // 播放/暂停大按钮
        SizedBox(
          width: 56,
          height: 56,
          child: IconButton(
            onPressed: isLoading ? null : _togglePlayPause,
            icon: isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                : Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
            color: accentColor,
            iconSize: 56,
            padding: EdgeInsets.zero,
            tooltip: isPlaying ? '暂停' : '播放',
          ),
        ),

        const SizedBox(width: 8),

        // 快进 15 秒
        IconButton(
          onPressed: isIdle
              ? null
              : _skipForward,
          icon: Icon(
            Icons.update,
            color: isIdle
                ? colorScheme.onSurface.withValues(alpha: 0.3)
                : colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          iconSize: 28,
          tooltip: '快进15秒',
        ),

        // 下一个事件按钮
        IconButton(
          onPressed: isIdle
              ? null
              : () => ref.read(playbackControlProvider.notifier).skipToNextEvent(),
          icon: Icon(
            Icons.skip_next,
            color: isIdle
                ? colorScheme.onSurface.withValues(alpha: 0.3)
                : colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          iconSize: 24,
          tooltip: '下一个事件',
        ),

        const SizedBox(width: 8),

        // 速度按钮
        _buildSpeedButton(colorScheme, speed),
      ],
    );
  }

  /// 构建播放速度按钮
  Widget _buildSpeedButton(ColorScheme colorScheme, double speed) {
    return InkWell(
      onTap: _cycleSpeed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${speed}x',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: speed != 1.0
                ? const Color(0xFF6B6BFF)
                : colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  /// 切换播放/暂停
  void _togglePlayPause() {
    final playbackStateAsync = ref.read(playbackStateProvider);
    final playbackState = playbackStateAsync.valueOrNull ?? PlaybackState.idle;

    if (playbackState == PlaybackState.playing) {
      ref.read(playbackControlProvider.notifier).pause();
    } else {
      ref.read(playbackControlProvider.notifier).play();
    }
  }

  /// 快退 15 秒
  void _skipBackward() {
    final positionAsync = ref.read(playbackPositionProvider);
    final position = positionAsync.valueOrNull ?? Duration.zero;
    final newPosition = (position.inMilliseconds - 15000).clamp(0, position.inMilliseconds);
    ref.read(playbackControlProvider.notifier).seekTo(newPosition);
  }

  /// 快进 15 秒
  void _skipForward() {
    final positionAsync = ref.read(playbackPositionProvider);
    final position = positionAsync.valueOrNull ?? Duration.zero;
    final duration = ref.read(playbackDurationProvider);
    final newPosition =
        (position.inMilliseconds + 15000).clamp(0, duration.inMilliseconds);
    ref.read(playbackControlProvider.notifier).seekTo(newPosition);
  }

  /// 循环切换播放速度
  void _cycleSpeed() {
    final currentSpeed = ref.read(playbackSpeedProvider);
    final currentIndex = _speedOptions.indexOf(currentSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    ref.read(playbackSpeedProvider.notifier).setSpeed(_speedOptions[nextIndex]);
  }

  /// 格式化播放位置为 MM:SS
  String _formatPosition(Duration duration) {
    return DateFormatUtil.formatDuration(duration.inMilliseconds);
  }
}
