import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/recording_segment.dart';
import '../../models/timeline_event.dart';

/// 事件显示模式枚举
///
/// 根据事件间的可用像素间距决定显示详细程度。
/// Author: GDNDZZK
enum EventDisplayMode {
  /// 紧凑模式：仅图标 + 标签（约 24dp）
  compact,

  /// 正常模式：图标 + 标签 + 时间戳 + 背景卡片（约 48dp）
  normal,

  /// 详细模式：图标 + 标签 + 时间戳 + 内容预览 + 缩略图（约 60-166dp）
  detailed,
}

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

  /// 事件点击回调（可选）
  ///
  /// 用户点击时间轴上的事件卡片时触发，由父组件处理详情展示。
  final void Function(TimelineEvent event)? onEventTap;

  const RecordingTimeline({
    super.key,
    required this.events,
    required this.segments,
    required this.totalElapsedMs,
    this.scrollController,
    this.onEventTap,
  });

  @override
  State<RecordingTimeline> createState() => _RecordingTimelineState();
}

class _RecordingTimelineState extends State<RecordingTimeline>
    with SingleTickerProviderStateMixin {
  ScrollController? _internalController;

  // ===== 动画 =====

  /// 仪表盘弹出/关闭动画控制器
  late final AnimationController _gaugeAnimController;

  @override
  void initState() {
    super.initState();
    _internalController = widget.scrollController ?? ScrollController();
    _gaugeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _gaugeAnimController.dispose();
    // 仅释放内部创建的控制器
    if (_internalController != null && widget.scrollController == null) {
      _internalController!.dispose();
    }
    super.dispose();
  }

  // ===== 连续缩放常量 =====

  /// 最宽松：30dp/s（30dp/s / 1000 = 0.03 dp/ms）
  static const double _maxPixelsPerMs = 0.03;

  /// 最紧凑：512x 缩放（0.03 / 512 ≈ 0.0000586 dp/ms）
  static const double _minPixelsPerMs = 0.03 / 512;

  /// 每次缩放的倍率
  static const double _zoomFactor = 2.0;

  /// 当前每毫秒对应的像素数（连续值）
  double _pixelsPerMs = _maxPixelsPerMs; // 初始为最宽松

  /// 是否显示扇形仪表盘
  bool _showZoomGauge = false;

  /// 是否已达到最紧凑（无法继续放大）
  bool get _canZoomIn => _pixelsPerMs > _minPixelsPerMs;

  /// 是否已达到最宽松（无法继续缩小）
  bool get _canZoomOut => _pixelsPerMs < _maxPixelsPerMs;

  /// 放大（更紧凑，pixelsPerMs 减小）
  void _zoomIn() {
    if (!_canZoomIn) return;
    setState(() {
      _pixelsPerMs =
          (_pixelsPerMs / _zoomFactor).clamp(_minPixelsPerMs, _maxPixelsPerMs);
    });
  }

  /// 缩小（更宽松，pixelsPerMs 增大）
  void _zoomOut() {
    if (!_canZoomOut) return;
    setState(() {
      _pixelsPerMs =
          (_pixelsPerMs * _zoomFactor).clamp(_minPixelsPerMs, _maxPixelsPerMs);
    });
  }

  /// 当前缩放倍率（1x = 最宽松，最大 512x）
  int get _zoomRatio => (_maxPixelsPerMs / _pixelsPerMs).round();

  // ===== 扇形仪表盘 =====

  /// 仪表盘尺寸
  static const double _gaugeWidth = 180.0;
  static const double _gaugeHeight = 130.0;

  /// 弧线圆心（在仪表盘局部坐标系中）
  static const double _gaugeCenterX = 160.0;
  static const double _gaugeCenterY = 115.0;

  /// 当前仪表盘值（0.0 = 1x, 1.0 = 512x）
  double get _gaugeValue {
    final zoomRatio = _maxPixelsPerMs / _pixelsPerMs;
    return math.log(math.max(1, zoomRatio)) / math.log(2) / 9;
  }

  /// 切换扇形仪表盘显示
  void _toggleZoomGauge() {
    setState(() {
      _showZoomGauge = !_showZoomGauge;
    });
    if (_showZoomGauge) {
      _gaugeAnimController.forward();
    } else {
      _gaugeAnimController.reverse();
    }
  }

  /// 关闭扇形仪表盘
  void _closeZoomGauge() {
    if (!_showZoomGauge) return;
    setState(() {
      _showZoomGauge = false;
    });
    _gaugeAnimController.reverse();
  }

  /// 处理仪表盘拖动开始
  void _handleGaugePanStart(DragStartDetails details) {
    _updateGaugeFromPosition(details.localPosition);
  }

  /// 处理仪表盘拖动更新
  void _handleGaugePanUpdate(DragUpdateDetails details) {
    _updateGaugeFromPosition(details.localPosition);
  }

  /// 处理仪表盘点击
  void _handleGaugeTap(TapUpDetails details) {
    _updateGaugeFromPosition(details.localPosition);
  }

  /// 根据触摸位置更新缩放值
  ///
  /// 仪表盘是四分之一圆弧，从左侧（1x）到上方（512x）。
  /// 圆心在右下角，弧线向左上方展开。
  void _updateGaugeFromPosition(Offset localPosition) {
    final dx = localPosition.dx - _gaugeCenterX;
    final dy = localPosition.dy - _gaugeCenterY;

    // 计算角度（屏幕坐标系：左 = π/-π，上 = -π/2）
    // 弧线范围：[-π, -π/2]（左上象限）
    var angle = math.atan2(dy, dx);

    // 处理超出弧线范围的触摸位置
    if (dy >= 0) {
      // 圆心下方：映射到 1x（左端）
      angle = -math.pi;
    } else if (dx >= 0) {
      // 圆心右上方：映射到 512x（上端）
      angle = -math.pi / 2;
    }
    // 左上象限：angle 已在 (-π, -π/2) 范围内

    // 钳制到弧线范围 [-π, -π/2]
    angle = angle.clamp(-math.pi, -math.pi / 2);

    // 映射到缩放值（对数刻度）：angle=-π → 0 (1x), angle=-π/2 → 1 (512x)
    final ratio = (angle + math.pi) / (math.pi / 2);
    final zoomRatio = math.pow(2, ratio * 9).toDouble();

    setState(() {
      _pixelsPerMs =
          (_maxPixelsPerMs / zoomRatio).clamp(_minPixelsPerMs, _maxPixelsPerMs);
    });
  }

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

  // ===== 显示模式高度常量 =====

  /// 紧凑模式高度（图标 + 单行文本）
  static const double _compactHeight = 24.0;

  /// 正常模式高度（图标 + 标签 + 时间戳 + 背景卡片）
  static const double _normalHeight = 48.0;

  /// 详细模式基础高度（图标 + 标签 + 时间戳）
  static const double _detailedBaseHeight = 60.0;

  /// 详细模式文本行高
  static const double _detailedLineHeight = 16.0;

  /// 详细模式最大文本行数
  static const int _detailedMaxLines = 3;

  /// 详细模式缩略图高度（64dp 缩略图 + 间距）
  static const double _detailedThumbnailHeight = 80.0;

  /// 同时间戳事件垂直偏移
  static const double _sameTimeOffset = 28.0;

  /// 最小事件间距
  static const double _minGap = 2.0;

  // ===== 颜色常量 =====

  /// 录音段颜色（绿色）
  static const Color _recordingColor = Color(0xFF4CAF50);

  /// 暂停段颜色（红色）
  static const Color _pausedColor = Color(0xFFE57373);

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

  /// 过滤掉 audio 类型的事件（录音信息已在时间轴段中显示）
  List<TimelineEvent> get _filteredEvents =>
      widget.events.where((e) => e.type != TimelineEventType.audio).toList();

  /// 估算事件在详细模式下的显示高度（dp）
  ///
  /// 根据事件内容动态计算：基础高度 + 文本行数 × 行高 + 缩略图高度。
  double _estimateEventHeight(TimelineEvent event) {
    double height = _detailedBaseHeight;

    // 文本内容高度
    if (event.textContent != null && event.textContent!.isNotEmpty) {
      // 估算文本行数（每行约 40 个字符）
      final lineCount = (event.textContent!.length / 40).ceil();
      final clampedLines = lineCount.clamp(1, _detailedMaxLines);
      height += clampedLines * _detailedLineHeight;
    }

    // 缩略图高度（照片/视频）
    if (event.thumbnailPath != null && event.thumbnailPath!.isNotEmpty) {
      height += _detailedThumbnailHeight;
    }

    return height;
  }

  /// 基于事件间像素间距计算每个事件的显示模式
  ///
  /// 从最后一个事件向前遍历，根据与下一个事件的像素间距决定最高可用显示级别。
  /// 同时间戳事件（差距 < 1ms）使用紧凑模式并添加垂直偏移。
  ///
  /// 返回一个记录，包含：
  /// - `modes`: 事件索引 → 显示模式的映射
  /// - `offsets`: 事件索引 → 垂直偏移的映射（用于同时间戳事件叠加显示）
  ({Map<int, EventDisplayMode> modes, Map<int, double> offsets})
      _calculateEventDisplayModes() {
    final events = _filteredEvents;
    final modes = <int, EventDisplayMode>{};
    final offsets = <int, double>{};

    if (events.isEmpty) return (modes: modes, offsets: offsets);

    // 计算每个事件的 Y 坐标
    final yPositions = events.map((e) => _msToY(e.timestamp)).toList();

    // 从最后一个事件向前遍历
    for (int i = events.length - 1; i >= 0; i--) {
      // 检查是否有同时间戳的后续事件，计算垂直偏移
      int sameTimeCount = 0;
      for (int j = i + 1; j < events.length; j++) {
        if ((events[j].timestamp - events[i].timestamp).abs() < 1) {
          sameTimeCount++;
        } else {
          break;
        }
      }

      // 同时间戳事件使用紧凑模式 + 垂直偏移
      if (sameTimeCount > 0) {
        modes[i] = EventDisplayMode.compact;
        offsets[i] = sameTimeCount * _sameTimeOffset;
        continue;
      }

      // 最后一个事件或没有后续事件约束：使用详细模式
      if (i == events.length - 1) {
        // 检查是否有同时间戳的前置事件
        bool isSameTimeAsPrev = false;
        if (i > 0) {
          isSameTimeAsPrev =
              (events[i].timestamp - events[i - 1].timestamp).abs() < 1;
        }
        modes[i] = isSameTimeAsPrev
            ? EventDisplayMode.compact
            : EventDisplayMode.detailed;
        continue;
      }

      // 计算与下一个事件的像素间距
      final gap = yPositions[i + 1] - yPositions[i];

      // 考虑下一个事件已分配的显示模式高度和偏移
      final nextMode = modes[i + 1]!;
      final nextHeight = _heightForMode(nextMode, events[i + 1]);
      final nextOffset = offsets[i + 1] ?? 0.0;

      // 可用间距 = 实际间距 - 下一个事件占据的高度 - 偏移
      final availableGap = gap - nextHeight - nextOffset;

      // 根据可用间距决定最高可用显示级别
      final detailedHeight = _estimateEventHeight(events[i]);

      if (availableGap >= detailedHeight) {
        modes[i] = EventDisplayMode.detailed;
      } else if (availableGap >= _normalHeight) {
        modes[i] = EventDisplayMode.normal;
      } else {
        modes[i] = EventDisplayMode.compact;
        // 如果间距不足，添加垂直偏移叠加显示
        if (availableGap < _compactHeight + _minGap) {
          // 计算需要偏移多少才能显示
          final overlapCount =
              ((nextHeight + nextOffset - gap) / _sameTimeOffset).ceil();
          offsets[i] = (overlapCount > 0 ? overlapCount : 1) * _sameTimeOffset;
        }
      }
    }

    return (modes: modes, offsets: offsets);
  }

  /// 获取指定显示模式对应的高度
  double _heightForMode(EventDisplayMode mode, TimelineEvent event) {
    switch (mode) {
      case EventDisplayMode.compact:
        return _compactHeight;
      case EventDisplayMode.normal:
        return _normalHeight;
      case EventDisplayMode.detailed:
        return _estimateEventHeight(event);
    }
  }

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
        // 点击仪表盘外部关闭
        if (_showZoomGauge)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeZoomGauge,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
        // 浮动缩放按钮
        _buildFloatingZoomButtons(theme, colorScheme),
        // 扇形仪表盘（带动画）
        if (_showZoomGauge || _gaugeAnimController.isAnimating)
          _buildAnimatedZoomGauge(theme, colorScheme),
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
  ///
  /// 使用基于重叠检测的自动折叠/展开逻辑，根据事件间实际像素间距
  /// 决定每个事件的显示模式。
  List<Widget> _buildEventMarkers(ThemeData theme, ColorScheme colorScheme) {
    final events = _filteredEvents;
    final displayResult = _calculateEventDisplayModes();
    final modes = displayResult.modes;
    final offsets = displayResult.offsets;

    return List.generate(events.length, (index) {
      final event = events[index];
      final y = _msToY(event.timestamp);
      final eventColor = _getEventColor(event.type, colorScheme, event.color);
      final icon = _getEventIcon(event.type);
      final displayMode = modes[index] ?? EventDisplayMode.compact;
      final verticalOffset = offsets[index] ?? 0.0;

      return Positioned(
        top: y - 12 + verticalOffset, // 垂直居中对齐时间轴线位置 + 偏移
        left: _eventLeft,
        right: 12,
        child: _buildEventCard(
          event: event,
          theme: theme,
          colorScheme: colorScheme,
          eventColor: eventColor,
          icon: icon,
          displayMode: displayMode,
        ),
      );
    });
  }

  /// 构建单个事件标记卡片
  ///
  /// 根据传入的 [displayMode] 显示不同详细程度的内容。
  /// 用 [GestureDetector] 包裹以支持点击交互。
  Widget _buildEventCard({
    required TimelineEvent event,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Color eventColor,
    required IconData icon,
    required EventDisplayMode displayMode,
  }) {
    final label = event.label ?? _getEventLabel(event.type);

    // 根据显示模式构建内容
    Widget content;
    switch (displayMode) {
      case EventDisplayMode.compact:
        // 紧凑模式：仅图标 + 标签
        content = Row(
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
        break;

      case EventDisplayMode.normal:
        // 正常模式：图标 + 标签 + 时间（带背景卡片）
        content = Container(
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
        break;

      case EventDisplayMode.detailed:
        // 详细模式：图标 + 标签 + 时间 + 内容预览 + 缩略图（带边框卡片）
        content = Container(
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
              if (event.textContent != null &&
                  event.textContent!.isNotEmpty) ...[
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
        break;
    }

    // 用 GestureDetector 包裹以支持点击交互
    return GestureDetector(
      onTap: () => widget.onEventTap?.call(event),
      behavior: HitTestBehavior.opaque,
      child: _TapFeedbackWrapper(child: content),
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
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
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
            // 当前缩放倍率指示（可点击弹出仪表盘）
            GestureDetector(
              onTap: _toggleZoomGauge,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '${_zoomRatio}x',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: _showZoomGauge
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight:
                        _showZoomGauge ? FontWeight.bold : FontWeight.normal,
                  ),
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

  // ==================== 扇形仪表盘 ====================

  /// 构建带动画的扇形仪表盘
  Widget _buildAnimatedZoomGauge(ThemeData theme, ColorScheme colorScheme) {
    return Positioned(
      right: 12,
      bottom: 100,
      child: AnimatedBuilder(
        animation: _gaugeAnimController,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.5 + 0.5 * _gaugeAnimController.value,
            alignment: Alignment.bottomRight,
            child: Opacity(
              opacity: _gaugeAnimController.value,
              child: child,
            ),
          );
        },
        child: _buildZoomGaugeContent(theme, colorScheme),
      ),
    );
  }

  /// 构建扇形仪表盘内容
  Widget _buildZoomGaugeContent(ThemeData theme, ColorScheme colorScheme) {
    return SizedBox(
      width: _gaugeWidth,
      height: _gaugeHeight,
      child: GestureDetector(
        onPanStart: _handleGaugePanStart,
        onPanUpdate: _handleGaugePanUpdate,
        onTapUp: _handleGaugeTap,
        child: CustomPaint(
          size: const Size(_gaugeWidth, _gaugeHeight),
          painter: _FanGaugePainter(
            value: _gaugeValue,
            currentLabel: '${_zoomRatio}x',
            primaryColor: colorScheme.primary,
            trackColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
            thumbColor: colorScheme.primary,
            textColor: colorScheme.onSurface,
            surfaceColor: colorScheme.surface,
          ),
        ),
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

// ==================== 点击反馈包装器 ====================

/// 事件卡片点击视觉反馈包装器
///
/// 按下时降低透明度，松开时恢复，提供视觉反馈。
/// Author: GDNDZZK
class _TapFeedbackWrapper extends StatefulWidget {
  final Widget child;

  const _TapFeedbackWrapper({required this.child});

  @override
  State<_TapFeedbackWrapper> createState() => _TapFeedbackWrapperState();
}

class _TapFeedbackWrapperState extends State<_TapFeedbackWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: AnimatedOpacity(
        opacity: _isPressed ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}

// ==================== 扇形仪表盘绘制器 ====================

/// 缩放扇形仪表盘自定义绘制器
///
/// 绘制四分之一圆弧仪表盘，从左侧（1x）到上方（512x）。
/// 圆心在右下角，弧线向左上方展开。
/// Author: GDNDZZK
class _FanGaugePainter extends CustomPainter {
  /// 当前值（0.0 = 1x 最宽松，1.0 = 512x 最紧凑）
  final double value;

  /// 当前缩放标签文字
  final String currentLabel;

  /// 主题色（活跃弧线和滑块）
  final Color primaryColor;

  /// 轨道颜色（背景弧线）
  final Color trackColor;

  /// 滑块颜色
  final Color thumbColor;

  /// 文字颜色
  final Color textColor;

  /// 表面颜色（滑块内圈）
  final Color surfaceColor;

  _FanGaugePainter({
    required this.value,
    required this.currentLabel,
    required this.primaryColor,
    required this.trackColor,
    required this.thumbColor,
    required this.textColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const centerX = 160.0;
    const centerY = 115.0;
    const radius = 85.0;
    const strokeWidth = 10.0;

    final arcRect = Rect.fromCircle(
      center: const Offset(centerX, centerY),
      radius: radius,
    );

    // 1. 绘制背景弧线
    // 四分之一圆弧：从左侧（π）顺时针到上方（3π/2 = -π/2）
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, math.pi, math.pi / 2, false, trackPaint);

    // 2. 绘制活跃弧线（从左侧 1x 到当前位置）
    if (value > 0.001) {
      final activePaint = Paint()
        ..color = primaryColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // 从左侧（π）顺时针扫过 value * π/2
      canvas.drawArc(arcRect, math.pi, value * math.pi / 2, false, activePaint);
    }

    // 3. 绘制刻度标记
    final tickPaint = Paint()
      ..color = textColor.withValues(alpha: 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 在每个 2 的幂次位置绘制刻度：1x, 2x, 4x, ..., 512x
    for (int i = 0; i <= 9; i++) {
      final ratio = i / 9;
      // 角度从 π（左侧 1x）到 3π/2（上方 512x）
      final angle = math.pi + ratio * math.pi / 2;
      final x = centerX + radius * math.cos(angle);
      final y = centerY + radius * math.sin(angle);

      // 刻度线方向：从弧线向外延伸
      final tickLength = (i % 3 == 0) ? 10.0 : 5.0;
      final nx = math.cos(angle);
      final ny = math.sin(angle);

      canvas.drawLine(
        Offset(x, y),
        Offset(x + nx * tickLength, y + ny * tickLength),
        tickPaint,
      );
    }

    // 4. 绘制滑块（圆形指示器）
    final thumbAngle = math.pi + value * math.pi / 2;
    final thumbX = centerX + radius * math.cos(thumbAngle);
    final thumbY = centerY + radius * math.sin(thumbAngle);

    // 发光效果
    final glowPaint = Paint()
      ..color = thumbColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, thumbY), 16, glowPaint);

    // 滑块主体
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, thumbY), 10, thumbPaint);

    // 滑块内圈
    final innerPaint = Paint()
      ..color = surfaceColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, thumbY), 5, innerPaint);

    // 5. 绘制标签
    // 左端标签 "1x"
    _drawLabel(
      canvas,
      '1x',
      centerX - radius - 16,
      centerY,
      textColor.withValues(alpha: 0.5),
      10,
    );

    // 上方标签 "512x"
    _drawLabel(
      canvas,
      '512x',
      centerX,
      centerY - radius - 16,
      textColor.withValues(alpha: 0.5),
      10,
    );

    // 当前值标签（在滑块附近）
    // 根据滑块位置调整标签偏移，避免与弧线重叠
    final labelOffsetX = thumbX + (thumbX < centerX ? -20.0 : 20.0);
    final labelOffsetY = thumbY + (thumbY < centerY ? -20.0 : 20.0);
    _drawLabel(
      canvas,
      currentLabel,
      labelOffsetX,
      labelOffsetY,
      primaryColor,
      13,
    );
  }

  /// 在指定位置绘制居中文字
  void _drawLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    Color color,
    double fontSize,
  ) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FanGaugePainter oldDelegate) {
    return value != oldDelegate.value || currentLabel != oldDelegate.currentLabel;
  }
}
