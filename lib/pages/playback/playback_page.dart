import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format_util.dart';
import '../../models/timeline_event.dart';
import '../../providers/playback_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/audio/audio_player_controls.dart';
import '../../widgets/common/image_viewer.dart';
import '../../widgets/timeline/playback_timeline.dart';

/// 回放页面
///
/// 提供音频回放、时间轴事件同步显示等功能。
/// 包含会话信息卡片、时间轴视图和底部音频播放控制栏。
/// Author: GDNDZZK
class PlaybackPage extends ConsumerStatefulWidget {
  /// 要回放的会话 ID
  final String sessionId;

  const PlaybackPage({super.key, required this.sessionId});

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  /// 会话信息卡片是否展开
  bool _isInfoExpanded = false;

  /// 是否已加载数据
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessionData();
    });
  }

  @override
  void dispose() {
    // 释放播放资源
    ref.read(playbackServiceProvider).dispose();
    super.dispose();
  }

  /// 加载会话数据
  Future<void> _loadSessionData() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(playbackControlProvider.notifier)
          .loadSession(widget.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载会话失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accentColor = Color(0xFF6B6BFF);

    // 监听播放状态
    final playbackStateAsync = ref.watch(playbackControlProvider);

    // 监听播放位置
    final positionAsync = ref.watch(playbackPositionProvider);
    final position = positionAsync.valueOrNull ?? Duration.zero;

    // 监听时间轴事件
    final eventsAsync = ref.watch(playbackEventsProvider);

    // 加载中状态
    if (_isLoading || playbackStateAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('加载中...'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 加载错误状态
    if (playbackStateAsync.hasError) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('回放'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${playbackStateAsync.error}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadSessionData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final events = eventsAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: _buildAppBar(context, theme, colorScheme, accentColor),
      body: Column(
        children: [
          // 会话信息卡片
          _buildSessionInfoCard(theme, colorScheme, accentColor, events),

          // 时间轴视图
          Expanded(
            child: PlaybackTimeline(
              events: events,
              currentPlaybackMs: position.inMilliseconds,
              onEventTap: (timestampMs) {
                ref
                    .read(playbackControlProvider.notifier)
                    .seekTo(timestampMs);
              },
              onPhotoTap: (event) => _handlePhotoTap(event),
              onNoteTap: (event) => _handleNoteTap(event, theme, colorScheme),
              onBookmarkTap: (event) =>
                  _handleBookmarkTap(event, theme, colorScheme),
              onVideoTap: (event) => _handleVideoTap(event),
            ),
          ),

          // 底部音频播放控制栏
          const AudioPlayerControls(accentColor: accentColor),
        ],
      ),
    );
  }

  /// 构建 AppBar
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Color accentColor,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: const Text('回放'),
      actions: [
        // 更多操作菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多操作',
          onSelected: (value) => _handleMenuAction(value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('编辑标题'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20),
                  SizedBox(width: 12),
                  Text('删除会话'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'ai',
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20),
                  SizedBox(width: 12),
                  Text('AI 功能'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建会话信息卡片
  Widget _buildSessionInfoCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Color accentColor,
    List<TimelineEvent> events,
  ) {
    // 统计各类型事件数量
    int photoCount = 0;
    int videoCount = 0;
    int noteCount = 0;
    int bookmarkCount = 0;

    for (final event in events) {
      switch (event.type) {
        case TimelineEventType.photo:
          photoCount++;
        case TimelineEventType.video:
          videoCount++;
        case TimelineEventType.textNote:
          noteCount++;
        case TimelineEventType.bookmark:
          bookmarkCount++;
      }
    }

    // 获取会话信息（尝试从 session list provider 获取）
    final sessionList = ref.watch(sessionListProvider);
    final session = sessionList.valueOrNull?.firstWhere(
      (s) => s.sessionId == widget.sessionId,
    );

    final title = session?.title ?? '回放';
    final createdAt = session?.createdAt ?? DateTime.now();
    final duration = session?.duration ?? 0;
    final audioDuration = session?.audioDuration ?? 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _isInfoExpanded = !_isInfoExpanded);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _isInfoExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),

              // 副标题行（始终显示）
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormatUtil.formatDateTime(createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormatUtil.formatDuration(duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),

              // 展开内容
              if (_isInfoExpanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // 录音时长
                if (audioDuration > 0)
                  Row(
                    children: [
                      Icon(
                        Icons.mic,
                        size: 14,
                        color: accentColor.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '录音时长: ${DateFormatUtil.formatDuration(audioDuration)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 8),

                // 事件统计
                Row(
                  children: [
                    if (photoCount > 0) ...[
                      _buildStatChip('📷', photoCount.toString()),
                      const SizedBox(width: 8),
                    ],
                    if (videoCount > 0) ...[
                      _buildStatChip('🎬', videoCount.toString()),
                      const SizedBox(width: 8),
                    ],
                    if (noteCount > 0) ...[
                      _buildStatChip('📝', noteCount.toString()),
                      const SizedBox(width: 8),
                    ],
                    if (bookmarkCount > 0) ...[
                      _buildStatChip('🔖', bookmarkCount.toString()),
                      const SizedBox(width: 8),
                    ],
                    if (events.isEmpty)
                      Text(
                        '暂无事件',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建统计标签
  Widget _buildStatChip(String emoji, String count) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$emoji $count',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
        ),
      ),
    );
  }

  // ==================== 事件详情处理 ====================

  /// 处理照片事件点击
  void _handlePhotoTap(TimelineEvent event) {
    if (event.thumbnail != null) {
      showImageViewer(
        context,
        imageData: event.thumbnail!,
        description: '照片 - ${_formatTimestamp(event.timestamp)}',
      );
    }
  }

  /// 处理笔记事件点击
  void _handleNoteTap(
    TimelineEvent event,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 拖拽指示条
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 标题
                Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      event.label ?? '笔记',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTimestamp(event.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // 内容
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Text(
                      event.textContent ?? '',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 处理书签事件点击
  void _handleBookmarkTap(
    TimelineEvent event,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final bookmarkColor = _parseColor(event.color);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bookmark, color: bookmarkColor),
            const SizedBox(width: 8),
            const Text('书签'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.label ?? '未命名书签',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(event.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '颜色: ',
                  style: theme.textTheme.bodySmall,
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: bookmarkColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(playbackControlProvider.notifier)
                  .seekTo(event.timestamp);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  /// 处理视频事件点击
  void _handleVideoTap(TimelineEvent event) {
    // 视频播放暂未实现，显示提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('视频播放功能即将推出'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ==================== 菜单操作 ====================

  /// 处理菜单操作
  void _handleMenuAction(String action) {
    switch (action) {
      case 'edit':
        _showEditTitleDialog();
        break;
      case 'delete':
        _showDeleteConfirmDialog();
        break;
      case 'ai':
        context.push('/ai/${widget.sessionId}');
        break;
    }
  }

  /// 显示编辑标题对话框
  void _showEditTitleDialog() {
    final sessionList = ref.read(sessionListProvider);
    final session = sessionList.valueOrNull?.firstWhere(
      (s) => s.sessionId == widget.sessionId,
    );

    final titleController = TextEditingController(
      text: session?.title ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑标题'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = titleController.text.trim();
              if (newTitle.isNotEmpty && session != null) {
                await ref
                    .read(sessionListProvider.notifier)
                    .updateSession(session.copyWith(title: newTitle));
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('确定要删除此会话吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(sessionListProvider.notifier)
                  .deleteSession(widget.sessionId);
              if (mounted) {
                this.context.pop();
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ==================== 工具方法 ====================

  /// 格式化时间戳（毫秒 → MM:SS）
  String _formatTimestamp(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = (duration.inMinutes).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
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
