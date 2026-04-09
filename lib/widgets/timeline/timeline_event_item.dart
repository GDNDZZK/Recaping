import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';
import 'zoomable_timeline.dart';

/// 单个时间轴事件节点展示组件
///
/// 布局：左侧时间 + 中间连接线/圆点 + 右侧内容卡片。
/// 不同事件类型显示不同的图标和内容。
/// 支持三种缩放级别：compact（紧凑）、normal（正常）、detailed（详细）。
/// Author: GDNDZZK
class TimelineEventItem extends StatelessWidget {
  /// 时间轴事件数据
  final TimelineEvent event;

  /// 点击回调
  final VoidCallback? onTap;

  /// 缩放级别（默认 normal）
  final TimelineZoomLevel zoomLevel;

  /// 是否高亮显示（回放时使用）
  final bool isHighlighted;

  const TimelineEventItem({
    super.key,
    required this.event,
    this.onTap,
    this.zoomLevel = TimelineZoomLevel.normal,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 时间戳格式化为 MM:SS
    final timestampStr = _formatTimestamp(event.timestamp);

    // 事件类型对应的颜色
    final dotColor = _getEventColor(event.type, colorScheme);

    // 缩放级别对应的间距
    final bottomPadding = getEventSpacing(zoomLevel);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧时间戳
          SizedBox(
            width: zoomLevel == TimelineZoomLevel.compact ? 40 : 48,
            child: Text(
              timestampStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isHighlighted
                    ? const Color(0xFF6B6BFF)
                    : colorScheme.onSurface.withValues(alpha: 0.6),
                fontFamily: 'monospace',
                fontSize: zoomLevel == TimelineZoomLevel.compact ? 10 : 11,
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
            child: _buildEventCard(context, theme, colorScheme, bottomPadding),
          ),
        ],
      ),
    );
  }

  /// 构建时间轴圆点和连接线
  Widget _buildTimelineDotAndLine(Color dotColor) {
    const accentColor = Color(0xFF6B6BFF);
    final dotSize = isHighlighted ? 14.0 : 12.0;

    return Column(
      children: [
        Container(
          width: dotSize,
          height: dotSize,
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
    double bottomPadding,
  ) {
    const accentColor = Color(0xFF6B6BFF);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
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
            padding: EdgeInsets.symmetric(
              horizontal: zoomLevel == TimelineZoomLevel.compact ? 8 : 12,
              vertical: zoomLevel == TimelineZoomLevel.compact ? 4 : 8,
            ),
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
      case TimelineEventType.audio:
        return _buildAudioContent(theme, colorScheme);
    }
  }

  /// 照片事件内容
  Widget _buildPhotoContent(ThemeData theme, ColorScheme colorScheme) {
    final thumbnailSize = getThumbnailSize(zoomLevel);

    // 紧凑模式：只显示图标和标签
    if (zoomLevel == TimelineZoomLevel.compact) {
      return Row(
        children: [
          Icon(Icons.camera_alt, size: 14, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            '拍照',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    // 详细模式：更大的缩略图
    if (zoomLevel == TimelineZoomLevel.detailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '拍照',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (event.thumbnail != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                event.thumbnail!,
                width: thumbnailSize,
                height: thumbnailSize,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(
                  width: thumbnailSize,
                  height: thumbnailSize,
                  child: const Icon(Icons.broken_image, size: 24),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // 正常模式
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
              width: thumbnailSize,
              height: thumbnailSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => SizedBox(
                width: thumbnailSize,
                height: thumbnailSize,
                child: const Icon(Icons.broken_image, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  /// 视频事件内容
  Widget _buildVideoContent(ThemeData theme, ColorScheme colorScheme) {
    final thumbnailSize = getThumbnailSize(zoomLevel);

    // 紧凑模式：只显示图标和标签
    if (zoomLevel == TimelineZoomLevel.compact) {
      return Row(
        children: [
          Icon(Icons.videocam, size: 14, color: colorScheme.tertiary),
          const SizedBox(width: 4),
          Text(
            '视频片段',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    // 详细模式：更大的缩略图
    if (zoomLevel == TimelineZoomLevel.detailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.videocam, size: 16, color: colorScheme.tertiary),
              const SizedBox(width: 6),
              Text(
                '视频片段',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (event.thumbnail != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                event.thumbnail!,
                width: thumbnailSize,
                height: thumbnailSize,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(
                  width: thumbnailSize,
                  height: thumbnailSize,
                  child: const Icon(Icons.broken_image, size: 24),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // 正常模式
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
              width: thumbnailSize,
              height: thumbnailSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => SizedBox(
                width: thumbnailSize,
                height: thumbnailSize,
                child: const Icon(Icons.broken_image, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  /// 文字笔记事件内容
  Widget _buildTextNoteContent(ThemeData theme, ColorScheme colorScheme) {
    final maxLines = getTextMaxLines(zoomLevel);

    // 紧凑模式：只显示图标和标题
    if (zoomLevel == TimelineZoomLevel.compact) {
      return Row(
        children: [
          Icon(Icons.edit_note, size: 14, color: colorScheme.secondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              event.label ?? '笔记',
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

    // 正常/详细模式
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
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// 书签事件内容
  Widget _buildBookmarkContent(ThemeData theme, ColorScheme colorScheme) {
    final bookmarkColor = _parseColor(event.color);

    // 紧凑模式：只显示图标和标签
    if (zoomLevel == TimelineZoomLevel.compact) {
      return Row(
        children: [
          Icon(Icons.bookmark, size: 14, color: bookmarkColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              event.label ?? '书签',
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

    // 正常/详细模式
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

  /// 录音区间事件内容
  Widget _buildAudioContent(ThemeData theme, ColorScheme colorScheme) {
    const audioColor = Color(0xFF4CAF50); // 绿色表示录音
    final durationMs = event.audioDurationMs;
    final durationStr = _formatDurationTag(durationMs);

    // 紧凑模式：只显示图标和标签
    if (zoomLevel == TimelineZoomLevel.compact) {
      return Row(
        children: [
          const Icon(Icons.mic, size: 14, color: audioColor),
          const SizedBox(width: 4),
          Text(
            '录音 $durationStr',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    // 正常/详细模式
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.mic, size: 16, color: audioColor),
            const SizedBox(width: 6),
            Text(
              '录音',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: audioColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                durationStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: audioColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        if (zoomLevel == TimelineZoomLevel.detailed && event.endTimestamp != null) ...[
          const SizedBox(height: 4),
          Text(
            '${_formatTimestamp(event.timestamp)} → ${_formatTimestamp(event.endTimestamp!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  /// 格式化时长标签（毫秒 → 可读字符串）
  String _formatDurationTag(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h${minutes.toString().padLeft(2, '0')}m';
    } else if (minutes > 0) {
      return '${minutes}m${seconds.toString().padLeft(2, '0')}s';
    } else {
      return '${seconds}s';
    }
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
      case TimelineEventType.audio:
        return const Color(0xFF4CAF50);
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
