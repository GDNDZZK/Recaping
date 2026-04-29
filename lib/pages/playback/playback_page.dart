import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/date_format_util.dart';
import '../../models/bookmark.dart';
import '../../models/text_note.dart';
import '../../models/timeline_event.dart';
import '../../providers/playback_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/audio/audio_player_controls.dart';
import '../../widgets/timeline/event_detail_panel.dart';
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
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
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
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
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

    // 获取会话信息以计算总时长
    final sessionList = ref.watch(sessionListProvider);
    final session = sessionList.valueOrNull
        ?.where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;
    final totalDurationMs = session?.duration ??
        (events.isNotEmpty
            ? events.map((e) => e.timestamp).reduce((a, b) => a > b ? a : b)
            : 0);

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
              totalDurationMs: totalDurationMs,
              onEventTap: (timestampMs) {
                ref
                    .read(playbackControlProvider.notifier)
                    .seekTo(timestampMs);
              },
              onPhotoTap: (event) => _handleEventDetail(event),
              onNoteTap: (event) => _handleEventDetail(event),
              onBookmarkTap: (event) => _handleEventDetail(event),
              onVideoTap: (event) => _handleEventDetail(event),
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
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
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
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_upload, size: 20),
                  SizedBox(width: 12),
                  Text('导出'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 12),
                  Text('分享'),
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
        case TimelineEventType.audio:
          // 录音区间事件不统计在快捷操作计数中
          break;
      }
    }

    // 获取会话信息（尝试从 session list provider 获取）
    final sessionList = ref.watch(sessionListProvider);
    final session = sessionList.valueOrNull
        ?.where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;

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

  /// 统一处理事件详情展示
  ///
  /// 使用 [EventDetailPanel] 显示事件详情，支持编辑和删除操作。
  /// 录音事件仅跳转播放位置，不显示详情面板。
  void _handleEventDetail(TimelineEvent event) {
    // 录音事件仅跳转播放位置
    if (event.type == TimelineEventType.audio) {
      ref.read(playbackControlProvider.notifier).seekTo(event.timestamp);
      return;
    }

    EventDetailPanel.show(
      context: context,
      event: event,
      onEdit: (updatedEvent) async {
        final eventsNotifier = ref.read(playbackEventsProvider.notifier);
        if (event.type == TimelineEventType.textNote) {
          final note = TextNote(
            id: event.id,
            timestamp: event.timestamp,
            title: updatedEvent.label,
            content: updatedEvent.textContent ?? '',
            createdAt: DateTime.now(),
          );
          await eventsNotifier.updateTextNote(note);
        } else if (event.type == TimelineEventType.bookmark) {
          final bookmark = Bookmark(
            id: event.id,
            timestamp: event.timestamp,
            label: updatedEvent.label,
            color: updatedEvent.color ?? '#FF6B6B',
            createdAt: DateTime.now(),
          );
          await eventsNotifier.updateBookmark(bookmark);
        }
      },
      onDelete: () async {
        final eventsNotifier = ref.read(playbackEventsProvider.notifier);
        await eventsNotifier.removeEvent(event.id, event.type);
      },
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
      case 'export':
        _handleExport();
        break;
      case 'share':
        _handleShare();
        break;
      case 'ai':
        context.push('/ai/${widget.sessionId}');
        break;
    }
  }

  /// 处理导出会话
  Future<void> _handleExport() async {
    try {
      final exportService = await ref.read(exportServiceProvider.future);
      final exportPath = await exportService.exportSession(widget.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出到: $exportPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 处理分享会话
  Future<void> _handleShare() async {
    try {
      final exportService = await ref.read(exportServiceProvider.future);
      // 获取会话标题
      final sessionList = ref.read(sessionListProvider);
      final session = sessionList.valueOrNull
          ?.where((s) => s.sessionId == widget.sessionId)
          .firstOrNull;
      await exportService.shareSession(
        widget.sessionId,
        title: session?.title,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  /// 显示编辑标题对话框
  void _showEditTitleDialog() {
    final sessionList = ref.read(sessionListProvider);
    final session = sessionList.valueOrNull
        ?.where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;

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

}

