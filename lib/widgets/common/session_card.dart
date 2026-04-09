import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/utils/date_format_util.dart';
import '../../models/session.dart';

/// 会话卡片组件
///
/// 可复用的会话卡片，显示会话缩略图、标题、时间、时长、事件数和标签。
/// 支持点击、长按和滑动删除操作。
/// Author: GDNDZZK
class SessionCard extends StatelessWidget {
  /// 会话数据
  final Session session;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 删除回调
  final VoidCallback? onDelete;

  /// 编辑回调
  final VoidCallback? onEdit;

  const SessionCard({
    super.key,
    required this.session,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.2,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete?.call(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 缩略图
                _buildThumbnail(colorScheme),
                const SizedBox(width: 12),
                // 会话信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        session.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 创建时间
                      Text(
                        DateFormatUtil.formatRelativeTime(session.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 时长和事件数
                      _buildMetaInfo(theme, colorScheme),
                      // 标签
                      if (session.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildTags(theme),
                      ],
                    ],
                  ),
                ),
                // 右侧箭头
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建缩略图
  Widget _buildThumbnail(ColorScheme colorScheme) {
    const size = 64.0;

    if (session.thumbnail != null && session.thumbnail!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          session.thumbnail!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(size, colorScheme),
        ),
      );
    }

    return _buildPlaceholder(size, colorScheme);
  }

  /// 构建占位缩略图
  Widget _buildPlaceholder(double size, ColorScheme colorScheme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.mic,
        color: colorScheme.onPrimaryContainer,
        size: 28,
      ),
    );
  }

  /// 构建元信息（时长 + 事件数）
  Widget _buildMetaInfo(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        // 时长
        Icon(
          Icons.schedule,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          DateFormatUtil.formatDuration(session.audioDuration),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        // 事件数
        if (session.eventCount > 0) ...[
          Icon(
            Icons.event_note,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '${session.eventCount} 个事件',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 构建标签列表
  Widget _buildTags(ThemeData theme) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: session.tags.take(3).map((tag) {
        return Chip(
          label: Text(
            tag,
            style: theme.textTheme.labelSmall,
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }
}
