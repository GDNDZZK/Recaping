import 'package:flutter/material.dart';

/// 播放头组件
///
/// 显示当前播放位置的指示器，类似PR等视频剪辑软件的播放头。
/// 支持竖向和横向两种方向。
/// Author: GDNDZZK
class TimelinePlayhead extends StatelessWidget {
  /// 当前位置（毫秒）
  final int positionMs;

  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 像素/毫秒比例
  final double pixelsPerMs;

  /// 方向（竖向或横向）
  final Axis direction;

  /// 播放头颜色
  final Color? color;

  /// 播放头宽度（竖向时）或高度（横向时）
  final double thickness;

  /// 是否显示时间标签
  final bool showTimeLabel;

  /// 时间标签位置（仅在竖向时有效）
  final TimeLabelPosition timeLabelPosition;

  const TimelinePlayhead({
    super.key,
    required this.positionMs,
    required this.totalDurationMs,
    this.pixelsPerMs = 0.1,
    this.direction = Axis.vertical,
    this.color,
    this.thickness = 2,
    this.showTimeLabel = true,
    this.timeLabelPosition = TimeLabelPosition.top,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playheadColor = color ?? const Color(0xFFFF4444);

    if (direction == Axis.vertical) {
      return _buildVerticalPlayhead(theme, colorScheme, playheadColor);
    } else {
      return _buildHorizontalPlayhead(theme, colorScheme, playheadColor);
    }
  }

  /// 构建竖向播放头
  Widget _buildVerticalPlayhead(ThemeData theme, ColorScheme colorScheme, Color playheadColor) {
    final position = positionMs * pixelsPerMs;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 播放头线
        Positioned(
          top: position,
          left: 0,
          right: 0,
          child: Container(
            height: thickness,
            color: playheadColor,
          ),
        ),

        // 播放头三角形指示器（左侧）
        Positioned(
          top: position - 6,
          left: 0,
          child: CustomPaint(
            size: const Size(12, 12),
            painter: _TrianglePainter(
              color: playheadColor,
              direction: TriangleDirection.right,
            ),
          ),
        ),

        // 时间标签
        if (showTimeLabel)
          Positioned(
            top: timeLabelPosition == TimeLabelPosition.top
                ? position - 24
                : position + 8,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: playheadColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatTime(positionMs),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 构建横向播放头
  Widget _buildHorizontalPlayhead(ThemeData theme, ColorScheme colorScheme, Color playheadColor) {
    final position = positionMs * pixelsPerMs;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 播放头线
        Positioned(
          left: position,
          top: 0,
          bottom: 0,
          child: Container(
            width: thickness,
            color: playheadColor,
          ),
        ),

        // 播放头三角形指示器（顶部）
        Positioned(
          left: position - 6,
          top: 0,
          child: CustomPaint(
            size: const Size(12, 12),
            painter: _TrianglePainter(
              color: playheadColor,
              direction: TriangleDirection.down,
            ),
          ),
        ),

        // 时间标签
        if (showTimeLabel)
          Positioned(
            left: position + 8,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: playheadColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatTime(positionMs),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 格式化时间（毫秒 → MM:SS.ms）
  String _formatTime(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final milliseconds = (ms % 1000) ~/ 10;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(2, '0')}';
    }
  }
}

/// 时间标签位置
enum TimeLabelPosition {
  top,
  bottom,
}

/// 三角形方向
enum TriangleDirection {
  left,
  right,
  up,
  down,
}

/// 三角形绘制器
class _TrianglePainter extends CustomPainter {
  final Color color;
  final TriangleDirection direction;

  _TrianglePainter({
    required this.color,
    required this.direction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();

    switch (direction) {
      case TriangleDirection.right:
        path.moveTo(0, 0);
        path.lineTo(size.width, size.height / 2);
        path.lineTo(0, size.height);
        break;
      case TriangleDirection.left:
        path.moveTo(size.width, 0);
        path.lineTo(0, size.height / 2);
        path.lineTo(size.width, size.height);
        break;
      case TriangleDirection.down:
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width / 2, size.height);
        break;
      case TriangleDirection.up:
        path.moveTo(0, size.height);
        path.lineTo(size.width, size.height);
        path.lineTo(size.width / 2, 0);
        break;
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.direction != direction;
  }
}

/// 播放头控制器
///
/// 用于控制播放头的位置和动画。
/// Author: GDNDZZK
class PlayheadController extends ChangeNotifier {
  /// 当前位置（毫秒）
  int _positionMs;

  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 是否正在播放
  bool _isPlaying = false;

  PlayheadController({
    int initialPositionMs = 0,
    required this.totalDurationMs,
  }) : _positionMs = initialPositionMs;

  /// 当前位置（毫秒）
  int get positionMs => _positionMs;

  /// 当前位置比例（0.0 - 1.0）
  double get positionRatio => totalDurationMs > 0 ? _positionMs / totalDurationMs : 0;

  /// 是否正在播放
  bool get isPlaying => _isPlaying;

  /// 设置位置
  set positionMs(int value) {
    final newPosition = value.clamp(0, totalDurationMs);
    if (_positionMs != newPosition) {
      _positionMs = newPosition;
      notifyListeners();
    }
  }

  /// 跳转到指定位置
  void seekTo(int ms) {
    positionMs = ms;
  }

  /// 前进指定毫秒
  void forward(int ms) {
    positionMs = _positionMs + ms;
  }

  /// 后退指定毫秒
  void backward(int ms) {
    positionMs = _positionMs - ms;
  }

  /// 开始播放
  void play() {
    _isPlaying = true;
    notifyListeners();
  }

  /// 暂停播放
  void pause() {
    _isPlaying = false;
    notifyListeners();
  }

  /// 停止播放（回到开头）
  void stop() {
    _isPlaying = false;
    _positionMs = 0;
    notifyListeners();
  }

  /// 更新播放位置（用于播放中的实时更新）
  void updatePosition(int ms) {
    _positionMs = ms.clamp(0, totalDurationMs);
    notifyListeners();
  }
}

/// 带播放头的滚动时间轴
///
/// 将播放头与可滚动的时间轴结合，支持自动滚动跟随。
/// Author: GDNDZZK
class ScrollableTimelineWithPlayhead extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 播放头控制器
  final PlayheadController controller;

  /// 滚动控制器
  final ScrollController? scrollController;

  /// 像素/毫秒比例
  final double pixelsPerMs;

  /// 方向
  final Axis direction;

  /// 是否自动滚动跟随播放头
  final bool autoScroll;

  /// 自动滚动边距（像素）
  final double autoScrollMargin;

  const ScrollableTimelineWithPlayhead({
    super.key,
    required this.child,
    required this.controller,
    this.scrollController,
    this.pixelsPerMs = 0.1,
    this.direction = Axis.vertical,
    this.autoScroll = true,
    this.autoScrollMargin = 100,
  });

  @override
  State<ScrollableTimelineWithPlayhead> createState() => _ScrollableTimelineWithPlayheadState();
}

class _ScrollableTimelineWithPlayheadState extends State<ScrollableTimelineWithPlayhead> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    widget.controller.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(ScrollableTimelineWithPlayhead oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPositionChanged);
      widget.controller.addListener(_onPositionChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPositionChanged);
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _onPositionChanged() {
    if (!widget.autoScroll || !_scrollController.hasClients) return;

    final position = widget.controller.positionMs * widget.pixelsPerMs;
    
    if (widget.direction == Axis.vertical) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentOffset = _scrollController.offset;

      // 如果播放头超出可视区域，自动滚动
      if (position < currentOffset + widget.autoScrollMargin) {
        _scrollController.animateTo(
          (position - widget.autoScrollMargin).clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      } else if (position > currentOffset + viewportHeight - widget.autoScrollMargin) {
        _scrollController.animateTo(
          (position - viewportHeight + widget.autoScrollMargin).clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    } else {
      final viewportWidth = _scrollController.position.viewportDimension;
      final currentOffset = _scrollController.offset;

      if (position < currentOffset + widget.autoScrollMargin) {
        _scrollController.animateTo(
          (position - widget.autoScrollMargin).clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      } else if (position > currentOffset + viewportWidth - widget.autoScrollMargin) {
        _scrollController.animateTo(
          (position - viewportWidth + widget.autoScrollMargin).clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 可滚动内容
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: widget.direction,
          child: widget.child,
        ),

        // 播放头
        Positioned.fill(
          child: IgnorePointer(
            child: TimelinePlayhead(
              positionMs: widget.controller.positionMs,
              totalDurationMs: widget.controller.totalDurationMs,
              pixelsPerMs: widget.pixelsPerMs,
              direction: widget.direction,
            ),
          ),
        ),
      ],
    );
  }
}
