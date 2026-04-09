import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';

/// 单个时间轴事件节点展示组件
///
/// 布局：左侧时间 + 中间连接线/圆点 + 右侧内容卡片。
/// 不同事件类型显示不同的图标和内容。
/// Author: GDNDZZK
class TimelineEventItem extends StatelessWidget {
  /// 时间轴事件数据
  final TimelineEvent event;

  /// 点击回调
  final VoidCallback? onTap;

  const TimelineEventItem({
    super.key,
    required this.event,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontFamily: 'monospace',
                fontSize: 11,
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
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
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
