import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';
import 'timeline_event_item.dart';
import 'zoomable_timeline.dart';

/// 回放专用的时间轴组件
///
/// 区别于录音时的实时时间轴，支持播放进度同步高亮和自动滚动。
/// 支持三种缩放级别：compact（紧凑）、normal（正常）、detailed（详细）。
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

  /// 当前缩放级别
  TimelineZoomLevel _zoomLevel = TimelineZoomLevel.normal;

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

      // 根据缩放级别估算每个事件项的高度
      final estimatedItemHeight = _getEstimatedItemHeight();
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

  /// 根据缩放级别获取估算的事件项高度
  double _getEstimatedItemHeight() {
    switch (_zoomLevel) {
      case TimelineZoomLevel.compact:
        return 40.0;
      case TimelineZoomLevel.normal:
        return 72.0;
      case TimelineZoomLevel.detailed:
        return 120.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ZoomableTimeline(
      initialZoomLevel: _zoomLevel,
      onZoomChanged: (level) {
        setState(() {
          _zoomLevel = level;
        });
        // 缩放后保持当前高亮事件可见
        if (_currentHighlightIndex >= 0) {
          _scrollToIndex(_currentHighlightIndex);
        }
      },
      child: widget.events.isEmpty
          ? Center(
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
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: widget.events.length,
              itemBuilder: (context, index) {
                final event = widget.events[index];
                final isHighlighted = index == _currentHighlightIndex;

                return TimelineEventItem(
                  event: event,
                  isHighlighted: isHighlighted,
                  zoomLevel: _zoomLevel,
                  onTap: () => _handleEventTap(event),
                );
              },
            ),
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
      case TimelineEventType.audio:
        // 录音区间事件点击仅跳转时间点，无额外回调
        break;
    }
  }
}
