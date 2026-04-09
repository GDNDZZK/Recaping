import 'package:flutter/material.dart';

import '../../models/timeline_event.dart';
import 'timeline_event_item.dart';
import 'zoomable_timeline.dart';

/// 录音过程中的实时时间轴组件
///
/// 纵向时间轴列表，展示所有已记录的事件节点。
/// 新事件添加时自动滚动到底部。
/// 支持三种缩放级别：compact（紧凑）、normal（正常）、detailed（详细）。
/// Author: GDNDZZK
class RecordingTimeline extends StatefulWidget {
  /// 时间轴事件列表
  final List<TimelineEvent> events;

  /// 滚动控制器（可选）
  final ScrollController? scrollController;

  const RecordingTimeline({
    super.key,
    required this.events,
    this.scrollController,
  });

  @override
  State<RecordingTimeline> createState() => _RecordingTimelineState();
}

class _RecordingTimelineState extends State<RecordingTimeline> {
  ScrollController? _internalController;

  /// 当前缩放级别
  TimelineZoomLevel _zoomLevel = TimelineZoomLevel.normal;

  @override
  void initState() {
    super.initState();
    _internalController = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(RecordingTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 事件数量增加时自动滚动到底部
    if (widget.events.length > oldWidget.events.length) {
      _scrollToBottom();
    }
  }

  /// 滚动到底部（最新事件）
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.scrollController ?? _internalController;
      if (controller != null && controller.hasClients) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    // 仅释放内部创建的控制器
    if (_internalController != null && widget.scrollController == null) {
      _internalController!.dispose();
    }
    super.dispose();
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
                      '录音过程中，事件将显示在这里',
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
              controller: widget.scrollController ?? _internalController,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: widget.events.length,
              itemBuilder: (context, index) {
                final event = widget.events[index];
                return TimelineEventItem(
                  event: event,
                  zoomLevel: _zoomLevel,
                );
              },
            ),
    );
  }
}
