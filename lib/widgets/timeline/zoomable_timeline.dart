import 'package:flutter/material.dart';

/// 时间轴缩放级别
enum TimelineZoomLevel {
  /// 紧凑模式：事件间距小，只显示图标和时间
  compact,

  /// 正常模式：默认间距，显示图标 + 时间 + 内容预览
  normal,

  /// 详细模式：事件间距大，显示完整内容和更大的缩略图
  detailed,
}

/// 可缩放时间轴包装器
///
/// 在时间轴顶部添加缩放按钮组，支持三种缩放级别切换。
/// 也可以通过双指缩放手势切换缩放级别。
/// Author: GDNDZZK
class ZoomableTimeline extends StatefulWidget {
  /// 实际的时间轴内容
  final Widget child;

  /// 缩放级别变化回调
  final ValueChanged<TimelineZoomLevel>? onZoomChanged;

  /// 初始缩放级别（默认 normal）
  final TimelineZoomLevel initialZoomLevel;

  /// 是否显示缩放控制按钮（默认 true）
  final bool showControls;

  const ZoomableTimeline({
    super.key,
    required this.child,
    this.onZoomChanged,
    this.initialZoomLevel = TimelineZoomLevel.normal,
    this.showControls = true,
  });

  @override
  State<ZoomableTimeline> createState() => ZoomableTimelineState();
}

/// 暴露 ZoomableTimeline 的 State，允许父组件通过
/// `GlobalKey<ZoomableTimelineState>` 访问和修改缩放级别。
class ZoomableTimelineState extends State<ZoomableTimeline> {
  late TimelineZoomLevel _zoomLevel;

  /// 当前缩放级别
  TimelineZoomLevel get zoomLevel => _zoomLevel;

  @override
  void initState() {
    super.initState();
    _zoomLevel = widget.initialZoomLevel;
  }

  /// 设置缩放级别
  void setZoomLevel(TimelineZoomLevel level) {
    if (_zoomLevel != level) {
      setState(() {
        _zoomLevel = level;
      });
      widget.onZoomChanged?.call(level);
    }
  }

  /// 切换到下一个缩放级别（循环）
  void cycleZoomLevel() {
    final nextIndex = (_zoomLevel.index + 1) % TimelineZoomLevel.values.length;
    setZoomLevel(TimelineZoomLevel.values[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 缩放控制按钮组
        if (widget.showControls) _buildZoomControls(theme, colorScheme),

        // 时间轴内容
        Flexible(child: widget.child),
      ],
    );
  }

  /// 构建缩放控制按钮组
  Widget _buildZoomControls(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 缩放标签
          Text(
            '缩放',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          // 三个缩放按钮
          _ZoomButton(
            icon: Icons.view_list,
            tooltip: '紧凑',
            isSelected: _zoomLevel == TimelineZoomLevel.compact,
            onPressed: () => setZoomLevel(TimelineZoomLevel.compact),
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(width: 2),
          _ZoomButton(
            icon: Icons.view_agenda,
            tooltip: '正常',
            isSelected: _zoomLevel == TimelineZoomLevel.normal,
            onPressed: () => setZoomLevel(TimelineZoomLevel.normal),
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(width: 2),
          _ZoomButton(
            icon: Icons.view_stream,
            tooltip: '详细',
            isSelected: _zoomLevel == TimelineZoomLevel.detailed,
            onPressed: () => setZoomLevel(TimelineZoomLevel.detailed),
            colorScheme: colorScheme,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

/// 缩放按钮组件
class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onPressed,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// 根据缩放级别获取事件项之间的间距
double getEventSpacing(TimelineZoomLevel zoomLevel) {
  switch (zoomLevel) {
    case TimelineZoomLevel.compact:
      return 4;
    case TimelineZoomLevel.normal:
      return 12;
    case TimelineZoomLevel.detailed:
      return 20;
  }
}

/// 根据缩放级别获取缩略图尺寸
double getThumbnailSize(TimelineZoomLevel zoomLevel) {
  switch (zoomLevel) {
    case TimelineZoomLevel.compact:
      return 0; // 不显示缩略图
    case TimelineZoomLevel.normal:
      return 36;
    case TimelineZoomLevel.detailed:
      return 64;
  }
}

/// 根据缩放级别获取文本最大行数
int getTextMaxLines(TimelineZoomLevel zoomLevel) {
  switch (zoomLevel) {
    case TimelineZoomLevel.compact:
      return 0; // 不显示文本内容
    case TimelineZoomLevel.normal:
      return 2;
    case TimelineZoomLevel.detailed:
      return 5;
  }
}
