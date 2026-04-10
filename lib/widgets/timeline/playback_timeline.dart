import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';
import 'timeline_event_item.dart';
import 'timeline_playhead.dart';
import 'timeline_ruler.dart';
import 'timeline_track.dart';
import 'zoomable_timeline.dart';

/// 回放专用的时间轴组件（PR风格改进版）
///
/// 类似Premiere Pro等视频剪辑软件的时间轴风格：
/// - 左侧显示时间刻度尺
/// - 中间是多轨道区域（录音轨道、照片轨道、视频轨道、笔记轨道、书签轨道）
/// - 播放头指示当前播放位置
/// - 支持缩放调整时间轴密度
///
/// Author: GDNDZZK
class PlaybackTimeline extends StatefulWidget {
  /// 时间轴事件列表
  final List<TimelineEvent> events;

  /// 当前播放位置（毫秒）
  final int currentPlaybackMs;

  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 点击事件回调（参数为事件时间戳毫秒）
  final Function(int) onEventTap;

  /// 点击照片事件回调（参数为事件对象）
  final void Function(TimelineEvent)? onPhotoTap;

  /// 点击笔记事件回调（参数为事件对象）
  final void Function(TimelineEvent)? onNoteTap;

  /// 点击书签事件回调（参数为事件对象）
  final void Function(TimelineEvent)? onBookmarkTap;

  /// 点击视频事件回调（参数为事件对象）
  final void Function(TimelineEvent)? onVideoTap;

  const PlaybackTimeline({
    super.key,
    required this.events,
    required this.currentPlaybackMs,
    required this.totalDurationMs,
    required this.onEventTap,
    this.onPhotoTap,
    this.onNoteTap,
    this.onBookmarkTap,
    this.onVideoTap,
  });

  @override
  State<PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<PlaybackTimeline> {
  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 当前高亮事件的索引
  int _currentHighlightIndex = -1;

  /// 当前缩放级别
  TimelineZoomLevel _zoomLevel = TimelineZoomLevel.normal;

  /// 像素/毫秒比例（根据缩放级别调整）
  double get _pixelsPerMs {
    switch (_zoomLevel) {
      case TimelineZoomLevel.compact:
        return 0.005; // 紧凑：5像素/秒
      case TimelineZoomLevel.normal:
        return 0.02; // 正常：20像素/秒
      case TimelineZoomLevel.detailed:
        return 0.05; // 详细：50像素/秒
    }
  }

  @override
  void initState() {
    super.initState();
    _updateHighlightIndex();
  }

  @override
  void didUpdateWidget(PlaybackTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPlaybackMs != oldWidget.currentPlaybackMs ||
        widget.events != oldWidget.events) {
      _updateHighlightIndex();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 根据当前播放位置更新高亮事件索引
  void _updateHighlightIndex() {
    if (widget.events.isEmpty) return;

    int newIndex = -1;
    for (int i = 0; i < widget.events.length; i++) {
      if (widget.events[i].timestamp <= widget.currentPlaybackMs) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _currentHighlightIndex) {
      final shouldScroll = _currentHighlightIndex != -1;
      setState(() {
        _currentHighlightIndex = newIndex;
      });

      // 自动滚动到当前高亮事件
      if (shouldScroll && newIndex >= 0) {
        _scrollToIndex(newIndex);
      }
    }
  }

  /// 滚动到指定索引的事件
  void _scrollToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      // 根据缩放级别估算每个事件项的高度
      final estimatedItemHeight = _getEstimatedItemHeight();
      const visibleHeight = 400.0;

      final targetOffset = (index * estimatedItemHeight) - (visibleHeight / 3);
      final maxScroll = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxScroll);

      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// 根据缩放级别获取估算的事件项高度
  double _getEstimatedItemHeight() {
    switch (_zoomLevel) {
      case TimelineZoomLevel.compact:
        return 40.0;
      case TimelineZoomLevel.normal:
        return 72.0;
      case TimelineZoomLevel.detailed:
        return 120.0;
    }
  }

  /// 将事件按类型分组
  Map<TrackType, List<TimelineEvent>> _groupEventsByType() {
    final groups = <TrackType, List<TimelineEvent>>{
      TrackType.audio: [],
      TrackType.photo: [],
      TrackType.video: [],
      TrackType.note: [],
      TrackType.bookmark: [],
    };

    for (final event in widget.events) {
      switch (event.type) {
        case TimelineEventType.audio:
          groups[TrackType.audio]!.add(event);
          break;
        case TimelineEventType.photo:
          groups[TrackType.photo]!.add(event);
          break;
        case TimelineEventType.video:
          groups[TrackType.video]!.add(event);
          break;
        case TimelineEventType.textNote:
          groups[TrackType.note]!.add(event);
          break;
        case TimelineEventType.bookmark:
          groups[TrackType.bookmark]!.add(event);
          break;
      }
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final eventGroups = _groupEventsByType();

    return ZoomableTimeline(
      initialZoomLevel: _zoomLevel,
      onZoomChanged: (level) {
        setState(() {
          _zoomLevel = level;
        });
        // 缩放后保持当前高亮事件可见
        if (_currentHighlightIndex >= 0) {
          _scrollToIndex(_currentHighlightIndex);
        }
      },
      child: widget.events.isEmpty
          ? _buildEmptyState(theme, colorScheme)
          : _buildTimelineContent(theme, colorScheme, eventGroups),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无时间轴事件',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建时间轴内容
  Widget _buildTimelineContent(
    ThemeData theme,
    ColorScheme colorScheme,
    Map<TrackType, List<TimelineEvent>> eventGroups,
  ) {
    // 计算总高度
    final totalHeight = widget.totalDurationMs * _pixelsPerMs;

    return Column(
      children: [
        // 轨道头部区域
        _buildTrackHeaders(eventGroups),

        // 时间轴主体区域
        Expanded(
          child: Row(
            children: [
              // 左侧时间刻度尺
              VerticalTimelineRuler(
                totalDurationMs: widget.totalDurationMs,
                viewportHeight: 400,
                pixelsPerMs: _pixelsPerMs,
                width: 60,
              ),

              // 右侧轨道区域
              Expanded(
                child: Stack(
                  children: [
                    // 可滚动的轨道内容
                    SingleChildScrollView(
                      controller: _scrollController,
                      child: SizedBox(
                        height: totalHeight.clamp(200, double.infinity),
                        child: Column(
                          children: [
                            // 录音轨道（显示为连续块）
                            if (eventGroups[TrackType.audio]!.isNotEmpty)
                              _buildAudioTrack(eventGroups[TrackType.audio]!),

                            // 其他事件列表
                            Expanded(
                              child: ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                itemCount: widget.events.length,
                                itemBuilder: (context, index) {
                                  final event = widget.events[index];
                                  // 跳过录音事件（已在轨道中显示）
                                  if (event.type == TimelineEventType.audio) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  final isHighlighted = index == _currentHighlightIndex;

                                  return TimelineEventItem(
                                    event: event,
                                    isHighlighted: isHighlighted,
                                    zoomLevel: _zoomLevel,
                                    onTap: () => _handleEventTap(event),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 播放头
                    TimelinePlayhead(
                      positionMs: widget.currentPlaybackMs,
                      totalDurationMs: widget.totalDurationMs,
                      pixelsPerMs: _pixelsPerMs,
                      direction: Axis.vertical,
                      showTimeLabel: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建轨道头部
  Widget _buildTrackHeaders(Map<TrackType, List<TimelineEvent>> eventGroups) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // 时间标签占位
          Container(
            width: 60,
            alignment: Alignment.center,
            child: Text(
              '时间',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // 轨道标签
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 录音轨道标签
                  if (eventGroups[TrackType.audio]!.isNotEmpty)
                    _buildTrackLabel(
                      '录音',
                      Icons.mic,
                      const Color(0xFF4CAF50),
                      eventGroups[TrackType.audio]!.length,
                    ),

                  // 照片轨道标签
                  if (eventGroups[TrackType.photo]!.isNotEmpty)
                    _buildTrackLabel(
                      '照片',
                      Icons.camera_alt,
                      colorScheme.primary,
                      eventGroups[TrackType.photo]!.length,
                    ),

                  // 视频轨道标签
                  if (eventGroups[TrackType.video]!.isNotEmpty)
                    _buildTrackLabel(
                      '视频',
                      Icons.videocam,
                      colorScheme.tertiary,
                      eventGroups[TrackType.video]!.length,
                    ),

                  // 笔记轨道标签
                  if (eventGroups[TrackType.note]!.isNotEmpty)
                    _buildTrackLabel(
                      '笔记',
                      Icons.edit_note,
                      colorScheme.secondary,
                      eventGroups[TrackType.note]!.length,
                    ),

                  // 书签轨道标签
                  if (eventGroups[TrackType.bookmark]!.isNotEmpty)
                    _buildTrackLabel(
                      '书签',
                      Icons.bookmark,
                      const Color(0xFFFF6B6B),
                      eventGroups[TrackType.bookmark]!.length,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建轨道标签
  Widget _buildTrackLabel(String name, IconData icon, Color color, int count) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建录音轨道（显示为连续块）
  Widget _buildAudioTrack(List<TimelineEvent> audioEvents) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const audioColor = Color(0xFF4CAF50);

    return Container(
      height: 60,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Stack(
        children: [
          // 背景网格
          CustomPaint(
            size: Size.infinite,
            painter: _TrackGridPainter(
              totalDurationMs: widget.totalDurationMs,
              pixelsPerMs: _pixelsPerMs,
              color: colorScheme.onSurface.withValues(alpha: 0.05),
            ),
          ),

          // 录音段
          ...audioEvents.map((event) {
            final startY = event.timestamp * _pixelsPerMs;
            final duration = event.audioDurationMs;
            final height = duration * _pixelsPerMs;

            return Positioned(
              top: startY,
              left: 8,
              right: 8,
              height: height.clamp(20, double.infinity),
              child: GestureDetector(
                onTap: () => widget.onEventTap(event.timestamp),
                child: Container(
                  decoration: BoxDecoration(
                    color: audioColor.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: audioColor.withValues(alpha: 0.9),
                      width: 1,
                    ),
                  ),
                  child: height > 30
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                event.label ?? '录音',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _formatDuration(event.audioDurationMs),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 格式化时长
  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m${seconds.toString().padLeft(2, '0')}s';
    } else {
      return '${seconds}s';
    }
  }

  /// 处理事件点击
  void _handleEventTap(TimelineEvent event) {
    // 跳转到事件时间点
    widget.onEventTap(event.timestamp);

    // 触发特定类型回调
    switch (event.type) {
      case TimelineEventType.photo:
        widget.onPhotoTap?.call(event);
        break;
      case TimelineEventType.video:
        widget.onVideoTap?.call(event);
        break;
      case TimelineEventType.textNote:
        widget.onNoteTap?.call(event);
        break;
      case TimelineEventType.bookmark:
        widget.onBookmarkTap?.call(event);
        break;
      case TimelineEventType.audio:
        // 录音区间事件点击仅跳转时间点，无额外回调
        break;
    }
  }
}

/// 轨道网格绘制器
class _TrackGridPainter extends CustomPainter {
  final int totalDurationMs;
  final double pixelsPerMs;
  final Color color;

  _TrackGridPainter({
    required this.totalDurationMs,
    required this.pixelsPerMs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final pixelsPerSecond = pixelsPerMs * 1000;

    // 根据缩放级别决定网格间隔
    double interval;
    if (pixelsPerSecond >= 50) {
      interval = 1000; // 1秒
    } else if (pixelsPerSecond >= 20) {
      interval = 5000; // 5秒
    } else if (pixelsPerSecond >= 10) {
      interval = 10000; // 10秒
    } else if (pixelsPerSecond >= 5) {
      interval = 30000; // 30秒
    } else {
      interval = 60000; // 1分钟
    }

    // 绘制水平网格线（时间线）
    for (double t = 0; t <= totalDurationMs; t += interval) {
      final y = t * pixelsPerMs;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackGridPainter oldDelegate) {
    return oldDelegate.totalDurationMs != totalDurationMs ||
        oldDelegate.pixelsPerMs != pixelsPerMs;
  }
}
