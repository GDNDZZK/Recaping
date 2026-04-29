import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/recording_segment.dart';
import '../../models/timeline_event.dart';

/// 录音时间轴组件（纵向持续延伸方案）
///
/// 布局：左侧时间标签 + 中间彩色时间轴线 + 右侧事件标记。
/// 绿色段（isRecording=true）表示录音中，红色段（isRecording=false）表示暂停间隔。
/// 时间轴始终显示并不断向下延伸，支持自动滚动和缩放。
/// Author: GDNDZZK
class RecordingTimeline extends StatefulWidget {
  /// 时间轴事件列表
  final List<TimelineEvent> events;

  /// 录音段列表
  final List<RecordingSegment> segments;

  /// 总已过时间（毫秒）
  final int totalElapsedMs;

  /// 滚动控制器（可选）
  final ScrollController? scrollController;

  const RecordingTimeline({
    super.key,
    required this.events,
    required this.segments,
    required this.totalElapsedMs,
    this.scrollController,
  });

  @override
  State<RecordingTimeline> createState() => _RecordingTimelineState();
}

class _RecordingTimelineState extends State<RecordingTimeline> {
  ScrollController? _internalController;

  // ===== 连续缩放常量 =====

  /// 最宽松：30dp/s（30dp/s / 1000 = 0.03 dp/ms）
  static const double _maxPixelsPerMs = 0.03;

  /// 最紧凑：512x 缩放（0.03 / 512 ≈ 0.0000586 dp/ms）
  static const double _minPixelsPerMs = 0.03 / 512;

  /// 每次缩放的倍率
  static const double _zoomFactor = 2.0;

  /// 当前每毫秒对应的像素数（连续值）
  double _pixelsPerMs = _maxPixelsPerMs; // 初始为最宽松

  /// 是否已达到最紧凑（无法继续放大）
  bool get _canZoomIn => _pixelsPerMs > _minPixelsPerMs;

  /// 是否已达到最宽松（无法继续缩小）
  bool get _canZoomOut => _pixelsPerMs < _maxPixelsPerMs;

  /// 放大（更紧凑，pixelsPerMs 减小）
  void _zoomIn() {
    if (!_canZoomIn) return;
    setState(() {
      _pixelsPerMs = (_pixelsPerMs / _zoomFactor).clamp(_minPixelsPerMs, _maxPixelsPerMs);
    });
  }

  /// 缩小（更宽松，pixelsPerMs 增大）
  void _zoomOut() {
    if (!_canZoomOut) return;
    setState(() {
      _pixelsPerMs = (_pixelsPerMs * _zoomFactor).clamp(_minPixelsPerMs, _maxPixelsPerMs);
    });
  }

  /// 当前缩放倍率（1x = 最宽松，最大 512x）
  int get _zoomRatio => (_maxPixelsPerMs / _pixelsPerMs).round();

  // ===== 布局常量 =====

  /// 时间标签列宽度
  static const double _timeLabelWidth = 44.0;

  /// 时间轴线左偏移
  static const double _timelineLeft = 52.0;

  /// 时间轴线宽度
  static const double _timelineWidth = 4.0;

  /// 段边界圆点尺寸
  static const double _dotSize = 12.0;

  /// 事件标记区域左偏移
  static const double _eventLeft = 68.0;

  // ===== 颜色常量 =====

  /// 录音段颜色（绿色）
  static const Color _recordingColor = Color(0xFF4CAF50);

  /// 暂停段颜色（红色）
  static const Color _pausedColor = Color(0xFFE57373);

  @override
  void initState() {
    super.initState();
    _internalController = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(RecordingTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 总时间增加时自动滚动到底部
    if (widget.totalElapsedMs > oldWidget.totalElapsedMs) {
      _scrollToBottom();
    }
  }

  /// 自动滚动到底部（仅在用户位于底部附近时）
  ///
  /// 如果用户手动向上滚动查看历史事件，则不强制滚动。
  /// 使用 [mounted] 检查确保 Widget 仍然有效。
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final controller = widget.scrollController ?? _internalController;
      if (controller != null && controller.hasClients) {
        final pos = controller.position;
        // 仅在用户位于底部附近（100dp 以内）时自动滚动
        if (pos.maxScrollExtent > 0 &&
            pos.pixels >= pos.maxScrollExtent - 100) {
          controller.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    // 仅释放内部创建的控制器
    if (_internalController != null && widget.scrollController == null) {
      _internalController!.dispose();
    }
    super.dispose();
  }

  /// 过滤掉 audio 类型的事件（录音信息已在时间轴段中显示）
  List<TimelineEvent> get _filteredEvents =>
      widget.events.where((e) => e.type != TimelineEventType.audio).toList();

  /// 根据当前缩放值动态计算合适的刻度间隔（毫秒）
  int _calculateTickIntervalMs() {
    final pixelsPerSec = _pixelsPerMs * 1000;
    // 目标：每个刻度间隔约 60dp
    final targetSec = 60.0 / pixelsPerSec;
    // 选择合适的时间间隔（包含更大的间隔以支持高缩放）
    const niceIntervals = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600];
    for (final sec in niceIntervals) {
      if (sec >= targetSec) return sec * 1000;
    }
    return 3600000; // 1 小时
  }

  /// 毫秒转 Y 坐标
  double _msToY(int ms) => ms.toDouble() * _pixelsPerMs;

  /// 格式化时间（M:SS 或 H:MM:SS）
  String _formatTime(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalMs = widget.totalElapsedMs;
    final hasSegments = widget.segments.isNotEmpty;

    // 直接管理缩放，不使用 ZoomableTimeline 包装器
    // （因为 ZoomableTimeline 的 initialZoomLevel 仅在初始化时生效，
    // 浮动按钮改变缩放级别后无法同步）
    if (!hasSegments) {
      return _buildEmptyState(theme, colorScheme);
    }
    return Stack(
      children: [
        _buildTimelineContent(theme, colorScheme, totalMs),
        // 浮动缩放按钮
        _buildFloatingZoomButtons(theme, colorScheme),
      ],
    );
  }

  /// 构建空状态提示
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
              '录音开始后，时间轴将显示在这里',
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

  /// 构建时间轴主体内容
  Widget _buildTimelineContent(
    ThemeData theme,
    ColorScheme colorScheme,
    int totalMs,
  ) {
    // 计算总高度：基于总时间 + 底部额外空间
    final contentHeight = totalMs > 0 ? _msToY(totalMs) + 100.0 : 100.0;
    final viewHeight = MediaQuery.of(context).size.height * 0.3;
    final totalHeight = contentHeight > viewHeight ? contentHeight : viewHeight;

    return SingleChildScrollView(
      controller: widget.scrollController ?? _internalController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. 时间刻度标签
            ..._buildTimeLabels(theme, totalMs),

            // 2. 刻度水平线（连接时间标签和时间轴线）
            ..._buildTickMarks(theme, totalMs),

            // 3. 时间轴线段（绿色/红色）
            ..._buildTimelineSegments(theme, totalMs),

            // 4. 段边界圆点
            ..._buildSegmentDots(),

            // 5. 事件连接线（从时间轴线到事件标记）
            ..._buildEventConnectors(theme),

            // 6. 事件标记卡片
            ..._buildEventMarkers(theme, colorScheme),

            // 7. 当前位置指示器
            if (totalMs > 0) _buildCurrentPositionIndicator(totalMs),
          ],
        ),
      ),
    );
  }

  // ==================== 时间刻度标签 ====================

  /// 构建左侧时间标签列表
  List<Widget> _buildTimeLabels(ThemeData theme, int totalMs) {
    if (totalMs <= 0) return [];

    final interval = _calculateTickIntervalMs();
    final labels = <Widget>[];

    for (int ms = 0; ms <= totalMs; ms += interval) {
      labels.add(
        Positioned(
          top: _msToY(ms) - 7, // 垂直居中对齐刻度线
          left: 0,
          width: _timeLabelWidth,
          child: Text(
            _formatTime(ms),
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      );
    }

    return labels;
  }

  // ==================== 刻度水平线 ====================

  /// 构建从时间标签到时间轴线的水平刻度线
  List<Widget> _buildTickMarks(ThemeData theme, int totalMs) {
    if (totalMs <= 0) return [];

    final interval = _calculateTickIntervalMs();
    final marks = <Widget>[];

    for (int ms = 0; ms <= totalMs; ms += interval) {
      marks.add(
        Positioned(
          top: _msToY(ms),
          left: _timeLabelWidth + 2,
          width: _timelineLeft - _timeLabelWidth - 2,
          height: 1,
          child: Container(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
      );
    }

    return marks;
  }

  // ==================== 时间轴线段 ====================

  /// 构建彩色时间轴线段
  List<Widget> _buildTimelineSegments(ThemeData theme, int totalMs) {
    final widgets = <Widget>[];

    // 背景线（浅灰色，作为默认底色）
    if (totalMs > 0) {
      widgets.add(
        Positioned(
          top: 0,
          left: _timelineLeft,
          width: _timelineWidth,
          height: _msToY(totalMs),
          child: Container(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
      );
    }

    // 彩色段（绿色=录音，红色=暂停）
    for (final segment in widget.segments) {
      final startY = _msToY(segment.startMs);
      final endMs = segment.endMs ?? totalMs;
      final height = _msToY(endMs) - startY;

      // 跳过高度为 0 的段
      if (height <= 0) continue;

      final color = segment.isRecording ? _recordingColor : _pausedColor;

      widgets.add(
        Positioned(
          top: startY,
          left: _timelineLeft,
          width: _timelineWidth,
          height: height,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              // 活跃段（endMs == null）添加发光效果
              boxShadow: segment.endMs == null
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  // ==================== 段边界圆点 ====================

  /// 构建每个段起始位置的圆点
  List<Widget> _buildSegmentDots() {
    return widget.segments.map((segment) {
      final y = _msToY(segment.startMs);
      final color = segment.isRecording ? _recordingColor : _pausedColor;

      return Positioned(
        top: y - _dotSize / 2,
        left: _timelineLeft + _timelineWidth / 2 - _dotSize / 2,
        child: Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      );
    }).toList();
  }

  // ==================== 事件连接线 ====================

  /// 构建从时间轴线到事件标记的水平连接线
  List<Widget> _buildEventConnectors(ThemeData theme) {
    return _filteredEvents.map((event) {
      final y = _msToY(event.timestamp);

      return Positioned(
        top: y,
        left: _timelineLeft + _timelineWidth,
        width: _eventLeft - _timelineLeft - _timelineWidth - 4,
        height: 1.5,
        child: Container(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
        ),
      );
    }).toList();
  }

  // ==================== 事件标记卡片 ====================

  /// 构建事件标记卡片列表
  List<Widget> _buildEventMarkers(ThemeData theme, ColorScheme colorScheme) {
    return _filteredEvents.map((event) {
      final y = _msToY(event.timestamp);
      final eventColor = _getEventColor(event.type, colorScheme, event.color);
      final icon = _getEventIcon(event.type);

      return Positioned(
        top: y - 12, // 垂直居中对齐时间轴线位置
        left: _eventLeft,
        right: 12,
        child: _buildEventCard(event, theme, colorScheme, eventColor, icon),
      );
    }).toList();
  }

  /// 构建单个事件标记卡片
  ///
  /// 根据缩放级别显示不同详细程度的内容。
  Widget _buildEventCard(
    TimelineEvent event,
    ThemeData theme,
    ColorScheme colorScheme,
    Color eventColor,
    IconData icon,
  ) {
    final label = event.label ?? _getEventLabel(event.type);

    // 根据 pixelsPerMs 决定事件卡片详细程度
    // 阈值：>0.01 为紧凑，>0.002 为正常，<=0.002 为详细
    final isCompact = _pixelsPerMs > 0.01;
    final isNormal = _pixelsPerMs > 0.002;

    // 紧凑模式：仅图标 + 标签
    if (isCompact) {
      return Row(
        children: [
          Icon(icon, size: 14, color: eventColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    // 正常模式：图标 + 标签 + 时间（带背景卡片）
    if (isNormal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: eventColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(event.timestamp),
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    // 详细模式：图标 + 标签 + 时间 + 内容预览 + 缩略图（带边框卡片）
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: eventColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: eventColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(event.timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          // 文本内容预览（笔记等）
          if (event.textContent != null && event.textContent!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              event.textContent!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // 缩略图（照片/视频）
          if (event.thumbnailPath != null &&
              event.thumbnailPath!.isNotEmpty) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(event.thumbnailPath!),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.broken_image, size: 24),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 当前位置指示器 ====================

  /// 构建当前时间位置指示器（蓝色发光圆点）
  Widget _buildCurrentPositionIndicator(int totalMs) {
    final y = _msToY(totalMs);

    return Positioned(
      top: y - 5,
      left: _timelineLeft - 3,
      child: Container(
        width: _timelineWidth + 6,
        height: _timelineWidth + 6,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 浮动缩放按钮 ====================

  /// 构建浮动缩放按钮组（右下角）
  Widget _buildFloatingZoomButtons(ThemeData theme, ColorScheme colorScheme) {
    return Positioned(
      right: 12,
      bottom: 16,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 放大按钮（更紧凑，pixelsPerMs 减小）
            _buildZoomButton(
              icon: Icons.add,
              tooltip: '放大',
              onPressed: _canZoomIn ? _zoomIn : null,
              theme: theme,
              colorScheme: colorScheme,
            ),
            // 当前缩放倍率指示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '${_zoomRatio}x',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            // 缩小按钮（更宽松，pixelsPerMs 增大）
            _buildZoomButton(
              icon: Icons.remove,
              tooltip: '缩小',
              onPressed: _canZoomOut ? _zoomOut : null,
              theme: theme,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单个缩放按钮
  Widget _buildZoomButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final isEnabled = onPressed != null;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        style: IconButton.styleFrom(
          foregroundColor: isEnabled
              ? colorScheme.onSurface
              : colorScheme.onSurface.withValues(alpha: 0.3),
          padding: EdgeInsets.zero,
        ),
        tooltip: tooltip,
      ),
    );
  }

  // ==================== 辅助方法 ====================

  /// 获取事件类型对应的颜色
  Color _getEventColor(
    TimelineEventType type,
    ColorScheme colorScheme,
    String? eventColor,
  ) {
    switch (type) {
      case TimelineEventType.photo:
        return colorScheme.primary;
      case TimelineEventType.video:
        return colorScheme.tertiary;
      case TimelineEventType.textNote:
        return colorScheme.secondary;
      case TimelineEventType.bookmark:
        return _parseColor(eventColor);
      case TimelineEventType.audio:
        return _recordingColor;
    }
  }

  /// 获取事件类型对应的图标
  IconData _getEventIcon(TimelineEventType type) {
    switch (type) {
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

  /// 获取事件类型的默认标签
  String _getEventLabel(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.photo:
        return '拍照';
      case TimelineEventType.video:
        return '视频片段';
      case TimelineEventType.textNote:
        return '笔记';
      case TimelineEventType.bookmark:
        return '书签';
      case TimelineEventType.audio:
        return '录音';
    }
  }

  /// 解析十六进制颜色字符串
  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) {
      return const Color(0xFFFF6B6B);
    }
    try {
      final hex = colorStr.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFFFF6B6B);
    }
  }
}
