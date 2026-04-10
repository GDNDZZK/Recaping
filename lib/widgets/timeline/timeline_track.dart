import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';

/// 轨道类型枚举
///
/// 定义时间轴上不同类型的轨道。
/// Author: GDNDZZK
enum TrackType {
  /// 录音轨道 - 显示为连续彩色块
  audio,
  /// 照片轨道 - 显示为标记点
  photo,
  /// 视频轨道 - 显示为标记点
  video,
  /// 笔记轨道 - 显示为标记点
  note,
  /// 书签轨道 - 显示为标记点
  bookmark,
}

/// 轨道数据模型
///
/// 表示时间轴上的一个轨道及其包含的事件。
/// Author: GDNDZZK
class TimelineTrackData {
  /// 轨道类型
  final TrackType type;

  /// 轨道名称
  final String name;

  /// 轨道图标
  final IconData icon;

  /// 轨道颜色
  final Color color;

  /// 轨道高度
  final double height;

  /// 轨道中的事件
  final List<TimelineEvent> events;

  const TimelineTrackData({
    required this.type,
    required this.name,
    required this.icon,
    required this.color,
    this.height = 40,
    this.events = const [],
  });
}

/// 时间轴轨道组件
///
/// 显示单个轨道及其事件，支持录音轨道（连续块）和标记轨道（点状标记）。
/// Author: GDNDZZK
class TimelineTrack extends StatelessWidget {
  /// 轨道数据
  final TimelineTrackData track;

  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 当前播放位置（毫秒）
  final int currentPositionMs;

  /// 像素/毫秒比例
  final double pixelsPerMs;

  /// 事件点击回调
  final Function(TimelineEvent)? onEventTap;

  /// 是否显示轨道标签
  final bool showLabel;

  const TimelineTrack({
    super.key,
    required this.track,
    required this.totalDurationMs,
    this.currentPositionMs = 0,
    this.pixelsPerMs = 0.1,
    this.onEventTap,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: track.height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 轨道标签
          if (showLabel)
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: track.color.withValues(alpha: 0.1),
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(track.icon, size: 14, color: track.color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      track.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: track.color,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (track.events.isNotEmpty)
                    Text(
                      '${track.events.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          
          // 轨道内容区域
          Expanded(
            child: _buildTrackContent(context, theme, colorScheme),
          ),
        ],
      ),
    );
  }

  /// 构建轨道内容
  Widget _buildTrackContent(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final totalWidth = totalDurationMs * pixelsPerMs;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // 背景网格线
            CustomPaint(
              size: Size(constraints.maxWidth, track.height),
              painter: _TrackGridPainter(
                totalDurationMs: totalDurationMs,
                pixelsPerMs: pixelsPerMs,
                color: colorScheme.onSurface.withValues(alpha: 0.05),
              ),
            ),
            
            // 事件内容
            SizedBox(
              width: totalWidth,
              height: track.height,
              child: track.type == TrackType.audio
                  ? _buildAudioTrackContent(theme, colorScheme)
                  : _buildMarkerTrackContent(theme, colorScheme),
            ),
          ],
        );
      },
    );
  }

  /// 构建录音轨道内容（连续块）
  Widget _buildAudioTrackContent(ThemeData theme, ColorScheme colorScheme) {
    return Stack(
      children: track.events.map((event) {
        final startX = event.timestamp * pixelsPerMs;
        final duration = event.audioDurationMs;
        final width = duration * pixelsPerMs;

        // 录音块
        return Positioned(
          left: startX,
          top: 4,
          bottom: 4,
          width: width.clamp(2, double.infinity),
          child: GestureDetector(
            onTap: () => onEventTap?.call(event),
            child: Container(
              decoration: BoxDecoration(
                color: track.color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: track.color.withValues(alpha: 0.9),
                  width: 1,
                ),
              ),
              child: width > 40
                  ? Center(
                      child: Text(
                        event.label ?? '录音',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 构建标记轨道内容（点状标记）
  Widget _buildMarkerTrackContent(ThemeData theme, ColorScheme colorScheme) {
    return Stack(
      children: track.events.map((event) {
        final x = event.timestamp * pixelsPerMs;
        final isCurrent = (event.timestamp - currentPositionMs).abs() < 500;

        return Positioned(
          left: x - 6,
          top: (track.height - 16) / 2,
          child: GestureDetector(
            onTap: () => onEventTap?.call(event),
            child: Container(
              width: 12,
              height: 16,
              decoration: BoxDecoration(
                color: isCurrent ? track.color : track.color.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: isCurrent ? Colors.white : track.color,
                  width: isCurrent ? 2 : 1,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: track.color.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  _getEventIcon(event),
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 获取事件图标
  IconData _getEventIcon(TimelineEvent event) {
    switch (event.type) {
      case TimelineEventType.photo:
        return Icons.camera_alt;
      case TimelineEventType.video:
        return Icons.videocam;
      case TimelineEventType.textNote:
        return Icons.edit_note;
      case TimelineEventType.bookmark:
        return Icons.bookmark;
      case TimelineEventType.audio:
        return Icons.mic;
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

    // 绘制垂直网格线
    for (double t = 0; t <= totalDurationMs; t += interval) {
      final x = t * pixelsPerMs;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
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

/// 多轨道时间轴组件
///
/// 显示多个轨道的时间轴，多轨道布局。
/// Author: GDNDZZK
class MultiTrackTimeline extends StatelessWidget {
  /// 轨道列表
  final List<TimelineTrackData> tracks;

  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 当前播放位置（毫秒）
  final int currentPositionMs;

  /// 像素/毫秒比例
  final double pixelsPerMs;

  /// 事件点击回调
  final Function(TimelineEvent)? onEventTap;

  /// 滚动控制器
  final ScrollController? scrollController;

  const MultiTrackTimeline({
    super.key,
    required this.tracks,
    required this.totalDurationMs,
    this.currentPositionMs = 0,
    this.pixelsPerMs = 0.1,
    this.onEventTap,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 轨道列表
          ...tracks.map((track) => TimelineTrack(
            track: track,
            totalDurationMs: totalDurationMs,
            currentPositionMs: currentPositionMs,
            pixelsPerMs: pixelsPerMs,
            onEventTap: onEventTap,
          )),
        ],
      ),
    );
  }
}

/// 轨道头部组件
///
/// 显示轨道名称和图标。
/// Author: GDNDZZK
class TrackHeader extends StatelessWidget {
  /// 轨道类型
  final TrackType type;

  /// 轨道名称
  final String name;

  /// 事件数量
  final int eventCount;

  /// 是否展开
  final bool isExpanded;

  /// 展开/收起回调
  final VoidCallback? onToggle;

  const TrackHeader({
    super.key,
    required this.type,
    required this.name,
    this.eventCount = 0,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _getTrackColor(type, colorScheme);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(_getTrackIcon(type), size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (eventCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$eventCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ),
          if (onToggle != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: color,
              ),
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ],
      ),
    );
  }

  /// 获取轨道颜色
  Color _getTrackColor(TrackType type, ColorScheme colorScheme) {
    switch (type) {
      case TrackType.audio:
        return const Color(0xFF4CAF50);
      case TrackType.photo:
        return colorScheme.primary;
      case TrackType.video:
        return colorScheme.tertiary;
      case TrackType.note:
        return colorScheme.secondary;
      case TrackType.bookmark:
        return const Color(0xFFFF6B6B);
    }
  }

  /// 获取轨道图标
  IconData _getTrackIcon(TrackType type) {
    switch (type) {
      case TrackType.audio:
        return Icons.mic;
      case TrackType.photo:
        return Icons.camera_alt;
      case TrackType.video:
        return Icons.videocam;
      case TrackType.note:
        return Icons.edit_note;
      case TrackType.bookmark:
        return Icons.bookmark;
    }
  }
}
