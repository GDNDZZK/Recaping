import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/utils/date_format_util.dart';
import '../../models/timeline_event.dart';
import '../common/image_viewer.dart';

/// 事件详情面板 - 支持查看、编辑、删除时间线事件
///
/// 使用 [showModalBottomSheet] 展示，内部使用 [DraggableScrollableSheet]
/// 实现可拖拽高度调节。
///
/// 使用方式：
/// ```dart
/// EventDetailPanel.show(
///   context: context,
///   event: event,
///   onEdit: (updatedEvent) { ... },
///   onDelete: () { ... },
/// );
/// ```
///
/// Author: GDNDZZK
class EventDetailPanel extends StatefulWidget {
  /// 要展示详情的事件
  final TimelineEvent event;

  /// 编辑回调，返回更新后的事件数据
  ///
  /// 仅 [TimelineEventType.textNote] 和 [TimelineEventType.bookmark] 类型会触发。
  final ValueChanged<TimelineEvent>? onEdit;

  /// 删除回调
  ///
  /// [TimelineEventType.audio] 类型不支持删除。
  final VoidCallback? onDelete;

  const EventDetailPanel({
    super.key,
    required this.event,
    this.onEdit,
    this.onDelete,
  });

  /// 显示事件详情面板
  ///
  /// [context] BuildContext
  /// [event] 要展示的事件
  /// [onEdit] 编辑回调（可选）
  /// [onDelete] 删除回调（可选）
  static Future<void> show({
    required BuildContext context,
    required TimelineEvent event,
    ValueChanged<TimelineEvent>? onEdit,
    VoidCallback? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventDetailPanel(
        event: event,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<EventDetailPanel> createState() => _EventDetailPanelState();
}

class _EventDetailPanelState extends State<EventDetailPanel> {
  /// 是否处于编辑模式
  bool _isEditing = false;

  /// 编辑模式下的标题控制器
  late TextEditingController _titleController;

  /// 编辑模式下的内容控制器（笔记用）
  late TextEditingController _contentController;

  /// 编辑模式下的标签控制器（书签用）
  late TextEditingController _labelController;

  /// 编辑模式下选中的颜色（书签用）
  late String _selectedColor;

  /// 预设颜色列表
  static const _presetColors = [
    '#FF6B6B', // 红色
    '#4ECDC4', // 青绿
    '#45B7D1', // 天蓝
    '#96CEB4', // 薄荷绿
    '#FFEAA7', // 淡黄
    '#DDA0DD', // 梅红
    '#98D8C8', // 水绿
    '#F7DC6F', // 金黄
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event.label ?? '');
    _contentController =
        TextEditingController(text: widget.event.textContent ?? '');
    _labelController = TextEditingController(text: widget.event.label ?? '');
    _selectedColor = widget.event.color ?? '#FF6B6B';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // 拖拽指示条
              _buildDragHandle(colorScheme),

              // 内容区域
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // 事件类型标题
                    _buildEventTypeHeader(theme, colorScheme),

                    const SizedBox(height: 16),

                    // 时间戳
                    _buildTimestampRow(theme, colorScheme),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // 事件内容（根据类型不同）
                    _buildEventContent(theme, colorScheme),

                    const SizedBox(height: 24),

                    // 底部操作按钮
                    _buildActionButtons(theme, colorScheme),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建拖拽指示条
  Widget _buildDragHandle(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// 构建事件类型标题（图标 + 类型名称）
  Widget _buildEventTypeHeader(ThemeData theme, ColorScheme colorScheme) {
    IconData icon;
    String typeName;
    Color iconColor;

    switch (widget.event.type) {
      case TimelineEventType.photo:
        icon = Icons.photo_camera;
        typeName = '照片';
        iconColor = colorScheme.primary;
      case TimelineEventType.video:
        icon = Icons.videocam;
        typeName = '视频';
        iconColor = colorScheme.tertiary;
      case TimelineEventType.textNote:
        icon = Icons.edit_note;
        typeName = '笔记';
        iconColor = colorScheme.secondary;
      case TimelineEventType.bookmark:
        icon = Icons.bookmark;
        typeName = '书签';
        iconColor = _parseColor(widget.event.color);
      case TimelineEventType.audio:
        icon = Icons.mic;
        typeName = '录音';
        iconColor = const Color(0xFF4CAF50);
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          typeName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// 构建时间戳行
  Widget _buildTimestampRow(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(
          Icons.access_time,
          size: 16,
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 6),
        Text(
          _formatTimestamp(widget.event.timestamp),
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        // 录音事件显示时长
        if (widget.event.type == TimelineEventType.audio &&
            widget.event.endTimestamp != null) ...[
          const SizedBox(width: 16),
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 4),
          Text(
            '时长 ${DateFormatUtil.formatDuration(widget.event.audioDurationMs)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  /// 构建事件内容（根据类型不同）
  Widget _buildEventContent(ThemeData theme, ColorScheme colorScheme) {
    switch (widget.event.type) {
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

  /// 构建照片内容
  Widget _buildPhotoContent(ThemeData theme, ColorScheme colorScheme) {
    final imagePath = widget.event.mediaFilePath ?? widget.event.thumbnailPath;
    if (imagePath == null) {
      return _buildMediaUnavailablePlaceholder(
        theme: theme,
        colorScheme: colorScheme,
        icon: Icons.broken_image,
        message: '图片不可用',
      );
    }

    // 检查文件是否存在
    final file = File(imagePath);
    if (!file.existsSync()) {
      return _buildMediaUnavailablePlaceholder(
        theme: theme,
        colorScheme: colorScheme,
        icon: Icons.broken_image,
        message: '图片文件不存在',
      );
    }

    return GestureDetector(
      onTap: () {
        // 点击图片全屏查看
        showImageViewer(
          context,
          filePath: imagePath,
          description: '照片',
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 200,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image,
                        size: 48,
                        color: colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '图片加载失败',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 构建视频内容
  Widget _buildVideoContent(ThemeData theme, ColorScheme colorScheme) {
    final thumbnailPath = widget.event.thumbnailPath;
    final mediaFilePath = widget.event.mediaFilePath;

    // 判断缩略图是否可用
    final hasThumbnail = thumbnailPath != null && File(thumbnailPath).existsSync();
    // 判断视频文件是否可用
    final hasVideoFile = mediaFilePath != null && File(mediaFilePath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 缩略图区域或占位图标
        GestureDetector(
          onTap: hasVideoFile ? () => _openVideoFile(mediaFilePath) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: hasThumbnail
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(
                        File(thumbnailPath),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 200,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildVideoPlaceholder(theme, colorScheme, hasVideoFile);
                        },
                      ),
                      // 播放按钮叠加层
                      if (hasVideoFile)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                    ],
                  )
                : _buildVideoPlaceholder(theme, colorScheme, hasVideoFile),
          ),
        ),

        // 视频文件信息和操作按钮
        if (hasVideoFile) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openVideoFile(mediaFilePath),
              icon: const Icon(Icons.play_circle_outline, size: 20),
              label: const Text('打开视频'),
            ),
          ),
        ] else if (mediaFilePath != null) ...[
          const SizedBox(height: 12),
          Text(
            '视频文件不存在',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  /// 构建视频占位符（无缩略图时显示）
  Widget _buildVideoPlaceholder(ThemeData theme, ColorScheme colorScheme, bool canOpen) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              canOpen ? Icons.play_circle_outline : Icons.videocam,
              size: 48,
              color: colorScheme.tertiary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              canOpen ? '点击播放视频' : '视频文件不可用',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建媒体不可用占位符（照片/视频通用）
  Widget _buildMediaUnavailablePlaceholder({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 使用系统播放器打开视频文件
  Future<void> _openVideoFile(String filePath) async {
    try {
      await OpenFilex.open(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法打开视频: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 构建文字笔记内容
  Widget _buildTextNoteContent(ThemeData theme, ColorScheme colorScheme) {
    if (_isEditing) {
      return _buildTextNoteEditMode(theme, colorScheme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        if (widget.event.label != null && widget.event.label!.isNotEmpty) ...[
          Text(
            widget.event.label!,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 内容
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.event.textContent ?? '',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  /// 构建笔记编辑模式
  Widget _buildTextNoteEditMode(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题输入框
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '标题（可选）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLength: 50,
        ),

        const SizedBox(height: 12),

        // 内容输入框
        TextField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: '笔记内容',
            border: OutlineInputBorder(),
            isDense: true,
            alignLabelWithHint: true,
          ),
          maxLines: 8,
          minLines: 4,
          maxLength: 500,
          autofocus: true,
        ),
      ],
    );
  }

  /// 构建书签内容
  Widget _buildBookmarkContent(ThemeData theme, ColorScheme colorScheme) {
    if (_isEditing) {
      return _buildBookmarkEditMode(theme, colorScheme);
    }

    final bookmarkColor = _parseColor(widget.event.color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: bookmarkColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.event.label ?? '未命名书签',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建书签编辑模式
  Widget _buildBookmarkEditMode(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签输入框
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(
            labelText: '标签（可选）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLength: 30,
          autofocus: true,
        ),

        const SizedBox(height: 16),

        // 颜色选择
        Text(
          '选择颜色',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presetColors.map((colorStr) {
            final color = _parseColor(colorStr);
            final isSelected = colorStr == _selectedColor;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = colorStr;
                });
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: colorScheme.onSurface,
                          width: 3,
                        )
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 构建录音内容
  Widget _buildAudioContent(ThemeData theme, ColorScheme colorScheme) {
    final durationMs = widget.event.audioDurationMs;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.mic,
            color: const Color(0xFF4CAF50).withValues(alpha: 0.7),
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.event.label ?? '录音',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '时长 ${DateFormatUtil.formatDuration(durationMs)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部操作按钮
  Widget _buildActionButtons(ThemeData theme, ColorScheme colorScheme) {
    // 录音事件不支持编辑或删除
    if (widget.event.type == TimelineEventType.audio) {
      return const SizedBox.shrink();
    }

    // 编辑模式下的按钮
    if (_isEditing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              setState(() => _isEditing = false);
            },
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _handleSave,
            child: const Text('保存'),
          ),
        ],
      );
    }

    // 查看模式下的按钮
    final canEdit = widget.event.type == TimelineEventType.textNote ||
        widget.event.type == TimelineEventType.bookmark;
    final canDelete = widget.onDelete != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 编辑按钮（仅笔记和书签支持）
        if (canEdit && widget.onEdit != null) ...[
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _isEditing = true);
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('编辑'),
          ),
          const SizedBox(width: 8),
        ],

        // 删除按钮
        if (canDelete)
          OutlinedButton.icon(
            onPressed: _handleDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: colorScheme.error,
            ),
            label: Text(
              '删除',
              style: TextStyle(color: colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            ),
          ),
      ],
    );
  }

  /// 处理保存编辑
  void _handleSave() {
    TimelineEvent updatedEvent;

    switch (widget.event.type) {
      case TimelineEventType.textNote:
        final title = _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim();
        final content = _contentController.text.trim();
        if (content.isEmpty) return;

        updatedEvent = widget.event.copyWith(
          label: title,
          textContent: content,
        );

      case TimelineEventType.bookmark:
        final label = _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim();
        updatedEvent = widget.event.copyWith(
          label: label,
          color: _selectedColor,
        );

      default:
        return;
    }

    widget.onEdit?.call(updatedEvent);
    Navigator.pop(context);
  }

  /// 处理删除（带二次确认）
  void _handleDelete() {
    final typeName = _getTypeName();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除$typeName'),
        content: Text('确定要删除这个$typeName吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              widget.onDelete?.call();
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 获取事件类型中文名称
  String _getTypeName() {
    switch (widget.event.type) {
      case TimelineEventType.photo:
        return '照片';
      case TimelineEventType.video:
        return '视频';
      case TimelineEventType.textNote:
        return '笔记';
      case TimelineEventType.bookmark:
        return '书签';
      case TimelineEventType.audio:
        return '录音';
    }
  }

  /// 格式化时间戳（毫秒 → 可读时间）
  String _formatTimestamp(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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
