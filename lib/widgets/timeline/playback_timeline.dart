import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';
import 'timeline_event_item.dart';

/// 回放专用的时间轴组件
///
/// 区别于录音时的实时时间轴，支持播放进度同步高亮和自动滚动。
/// Author: GDNDZZK
class PlaybackTimeline extends StatefulWidget {
  /// 时间轴事件列表
  final List<TimelineEvent> events;

  /// 当前播放位置（毫秒）
  final int currentPlaybackMs;

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

      // 估算每个事件项的高度（约 72 像素）
      const estimatedItemHeight = 72.0;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.events.isEmpty) {
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: widget.events.length,
      itemBuilder: (context, index) {
        final event = widget.events[index];
        final isHighlighted = index == _currentHighlightIndex;

        return _PlaybackTimelineEventItem(
          event: event,
          isHighlighted: isHighlighted,
          onTap: () => _handleEventTap(event),
        );
      },
    );
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
    }
  }
}

/// 回放时间轴中的单个事件项
///
/// 在 [TimelineEventItem] 基础上增加高亮效果。
/// Author: GDNDZZK
class _PlaybackTimelineEventItem extends StatelessWidget {
  final TimelineEvent event;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _PlaybackTimelineEventItem({
    required this.event,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accentColor = Color(0xFF6B6BFF);

    // 时间戳格式化为 MM:SS
    final timestampStr = _formatTimestamp(event.timestamp);

    // 事件类型对应的颜色
    final dotColor = _getEventColor(event.type, colorScheme);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧时间戳
          SizedBox(
            width: 48,
            child: Text(
              timestampStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isHighlighted
                    ? accentColor
                    : colorScheme.onSurface.withValues(alpha: 0.6),
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.right,
            ),
          ),

          const SizedBox(width: 8),

          // 中间连接线 + 圆点
          _buildTimelineDotAndLine(dotColor),

          const SizedBox(width: 8),

          // 右侧内容卡片
          Expanded(
            child: _buildEventCard(context, theme, colorScheme),
          ),
        ],
      ),
    );
  }

  /// 构建时间轴圆点和连接线
  Widget _buildTimelineDotAndLine(Color dotColor) {
    const accentColor = Color(0xFF6B6BFF);

    return Column(
      children: [
        Container(
          width: isHighlighted ? 14 : 12,
          height: isHighlighted ? 14 : 12,
          decoration: BoxDecoration(
            color: isHighlighted ? accentColor : dotColor,
            shape: BoxShape.circle,
            border: isHighlighted
                ? Border.all(
                    color: accentColor.withValues(alpha: 0.3),
                    width: 3,
                  )
                : null,
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        Expanded(
          child: Container(
            width: 2,
            color: dotColor.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  /// 构建事件内容卡片
  Widget _buildEventCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    const accentColor = Color(0xFF6B6BFF);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isHighlighted
            ? accentColor.withValues(alpha: 0.1)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isHighlighted
                  ? Border.all(
                      color: accentColor.withValues(alpha: 0.5),
                      width: 1.5,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _buildEventContent(theme, colorScheme),
          ),
        ),
      ),
    );
  }

  /// 根据事件类型构建内容
  Widget _buildEventContent(ThemeData theme, ColorScheme colorScheme) {
    switch (event.type) {
      case TimelineEventType.photo:
        return _buildPhotoContent(theme, colorScheme);
      case TimelineEventType.video:
        return _buildVideoContent(theme, colorScheme);
      case TimelineEventType.textNote:
        return _buildTextNoteContent(theme, colorScheme);
      case TimelineEventType.bookmark:
        return _buildBookmarkContent(theme, colorScheme);
    }
  }

  /// 照片事件内容
  Widget _buildPhotoContent(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.camera_alt, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          '拍照',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (event.thumbnail != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              event.thumbnail!,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.broken_image, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  /// 视频事件内容
  Widget _buildVideoContent(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.videocam, size: 16, color: colorScheme.tertiary),
        const SizedBox(width: 6),
        Text(
          '视频片段',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (event.thumbnail != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              event.thumbnail!,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.broken_image, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  /// 文字笔记事件内容
  Widget _buildTextNoteContent(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.edit_note, size: 16, color: colorScheme.secondary),
            const SizedBox(width: 6),
            Text(
              event.label ?? '笔记',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (event.textContent != null && event.textContent!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            event.textContent!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// 书签事件内容
  Widget _buildBookmarkContent(ThemeData theme, ColorScheme colorScheme) {
    final bookmarkColor = _parseColor(event.color);

    return Row(
      children: [
        Icon(Icons.bookmark, size: 16, color: bookmarkColor),
        const SizedBox(width: 6),
        Text(
          event.label ?? '书签',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: bookmarkColor,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  /// 格式化时间戳（毫秒 → MM:SS）
  String _formatTimestamp(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = (duration.inMinutes).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 获取事件类型对应的颜色
  Color _getEventColor(TimelineEventType type, ColorScheme colorScheme) {
    switch (type) {
      case TimelineEventType.photo:
        return colorScheme.primary;
      case TimelineEventType.video:
        return colorScheme.tertiary;
      case TimelineEventType.textNote:
        return colorScheme.secondary;
      case TimelineEventType.bookmark:
        return _parseColor(event.color);
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
