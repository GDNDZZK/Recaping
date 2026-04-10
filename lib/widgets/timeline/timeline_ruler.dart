import 'package:flutter/material.dart';

/// 时间轴刻度尺组件
///
/// 显示时间刻度线（秒、分钟标记），类似PR等视频剪辑软件的时间轴刻度。
/// 支持缩放级别调整刻度密度。
/// Author: GDNDZZK
class TimelineRuler extends StatelessWidget {
  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 当前缩放级别（像素/秒）
  final double pixelsPerSecond;

  /// 刻度颜色
  final Color? tickColor;

  /// 背景颜色
  final Color? backgroundColor;

  /// 刻度高度
  final double height;

  const TimelineRuler({
    super.key,
    required this.totalDurationMs,
    this.pixelsPerSecond = 10.0,
    this.tickColor,
    this.backgroundColor,
    this.height = 32,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tickColorValue = tickColor ?? colorScheme.onSurface.withValues(alpha: 0.3);
    final bgColorValue = backgroundColor ?? colorScheme.surfaceContainerLow;

    final totalSeconds = totalDurationMs / 1000;
    final totalWidth = totalSeconds * pixelsPerSecond;

    return Container(
      height: height,
      color: bgColorValue,
      child: CustomPaint(
        size: Size(totalWidth, height),
        painter: _TimelineRulerPainter(
          totalDurationMs: totalDurationMs,
          pixelsPerSecond: pixelsPerSecond,
          tickColor: tickColorValue,
          textStyle: theme.textTheme.labelSmall?.copyWith(
            color: tickColorValue,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// 时间轴刻度尺绘制器
class _TimelineRulerPainter extends CustomPainter {
  final int totalDurationMs;
  final double pixelsPerSecond;
  final Color tickColor;
  final TextStyle? textStyle;

  _TimelineRulerPainter({
    required this.totalDurationMs,
    required this.pixelsPerSecond,
    required this.tickColor,
    this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalSeconds = totalDurationMs / 1000;
    
    // 根据缩放级别决定刻度间隔
    final (majorInterval, minorInterval, showLabels) = _getIntervals();

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1;

    final majorTickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;

    // 绘制主刻度（分钟）
    for (double t = 0; t <= totalSeconds; t += majorInterval) {
      final x = t * pixelsPerSecond;
      
      // 主刻度线
      canvas.drawLine(
        Offset(x, size.height * 0.3),
        Offset(x, size.height),
        majorTickPaint,
      );

      // 时间标签
      if (showLabels && textStyle != null) {
        final label = _formatTime(t * 1000);
        final textSpan = TextSpan(text: label, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 4, 2));
      }
    }

    // 绘制次刻度（秒）
    for (double t = 0; t <= totalSeconds; t += minorInterval) {
      // 跳过主刻度位置
      if (t % majorInterval < 0.001) continue;
      
      final x = t * pixelsPerSecond;
      final tickHeight = (t % (majorInterval / 2) < 0.001) 
          ? size.height * 0.5  // 半分钟刻度稍长
          : size.height * 0.7; // 普通秒刻度

      canvas.drawLine(
        Offset(x, tickHeight),
        Offset(x, size.height),
        tickPaint,
      );
    }

    // 绘制底部横线
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      tickPaint,
    );
  }

  /// 根据缩放级别获取刻度间隔
  (double major, double minor, bool showLabels) _getIntervals() {
    // pixelsPerSecond 越大，显示越详细
    if (pixelsPerSecond >= 50) {
      // 很详细：每10秒主刻度，每1秒次刻度
      return (10.0, 1.0, true);
    } else if (pixelsPerSecond >= 20) {
      // 详细：每30秒主刻度，每5秒次刻度
      return (30.0, 5.0, true);
    } else if (pixelsPerSecond >= 10) {
      // 正常：每1分钟主刻度，每10秒次刻度
      return (60.0, 10.0, true);
    } else if (pixelsPerSecond >= 5) {
      // 紧凑：每2分钟主刻度，每30秒次刻度
      return (120.0, 30.0, true);
    } else {
      // 很紧凑：每5分钟主刻度，每1分钟次刻度
      return (300.0, 60.0, pixelsPerSecond >= 2);
    }
  }

  /// 格式化时间（毫秒 → MM:SS 或 HH:MM:SS）
  String _formatTime(double ms) {
    final duration = Duration(milliseconds: ms.round());
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.totalDurationMs != totalDurationMs ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.tickColor != tickColor;
  }
}

/// 竖向时间轴刻度尺（用于左侧时间显示）
///
/// 在竖向滚动的时间轴左侧显示时间刻度。
/// Author: GDNDZZK
class VerticalTimelineRuler extends StatelessWidget {
  /// 总时长（毫秒）
  final int totalDurationMs;

  /// 当前滚动偏移（毫秒）
  final int scrollOffsetMs;

  /// 可视区域高度
  final double viewportHeight;

  /// 像素/毫秒比例
  final double pixelsPerMs;

  /// 刻度颜色
  final Color? tickColor;

  /// 背景颜色
  final Color? backgroundColor;

  /// 宽度
  final double width;

  const VerticalTimelineRuler({
    super.key,
    required this.totalDurationMs,
    this.scrollOffsetMs = 0,
    this.viewportHeight = 400,
    this.pixelsPerMs = 0.1,
    this.tickColor,
    this.backgroundColor,
    this.width = 60,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tickColorValue = tickColor ?? colorScheme.onSurface.withValues(alpha: 0.3);
    final bgColorValue = backgroundColor ?? colorScheme.surfaceContainerLow;

    return Container(
      width: width,
      color: bgColorValue,
      child: CustomPaint(
        size: Size(width, viewportHeight),
        painter: _VerticalRulerPainter(
          totalDurationMs: totalDurationMs,
          scrollOffsetMs: scrollOffsetMs,
          viewportHeight: viewportHeight,
          pixelsPerMs: pixelsPerMs,
          tickColor: tickColorValue,
          textStyle: theme.textTheme.labelSmall?.copyWith(
            color: tickColorValue,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// 竖向刻度尺绘制器
class _VerticalRulerPainter extends CustomPainter {
  final int totalDurationMs;
  final int scrollOffsetMs;
  final double viewportHeight;
  final double pixelsPerMs;
  final Color tickColor;
  final TextStyle? textStyle;

  _VerticalRulerPainter({
    required this.totalDurationMs,
    required this.scrollOffsetMs,
    required this.viewportHeight,
    required this.pixelsPerMs,
    required this.tickColor,
    this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pixelsPerSecond = pixelsPerMs * 1000;
    
    // 计算可见时间范围
    final startMs = scrollOffsetMs;
    final endMs = (scrollOffsetMs + viewportHeight / pixelsPerMs).round();
    
    // 根据缩放级别决定刻度间隔
    final (majorInterval, minorInterval) = _getIntervals(pixelsPerSecond);

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1;

    final majorTickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;

    // 绘制主刻度
    for (int t = startMs - (startMs % majorInterval); t <= endMs && t <= totalDurationMs; t += majorInterval) {
      if (t < 0) continue;
      
      final y = (t - startMs) * pixelsPerMs;
      
      // 主刻度线
      canvas.drawLine(
        Offset(size.width * 0.3, y),
        Offset(size.width, y),
        majorTickPaint,
      );

      // 时间标签
      if (textStyle != null) {
        final label = _formatTime(t);
        final textSpan = TextSpan(text: label, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(4, y - textPainter.height / 2));
      }
    }

    // 绘制次刻度
    for (int t = startMs - (startMs % minorInterval); t <= endMs && t <= totalDurationMs; t += minorInterval) {
      if (t < 0) continue;
      if (t % majorInterval < minorInterval / 2) continue; // 跳过主刻度
      
      final y = (t - startMs) * pixelsPerMs;
      final tickWidth = (t % (majorInterval / 2) < minorInterval / 2) 
          ? size.width * 0.5
          : size.width * 0.7;

      canvas.drawLine(
        Offset(tickWidth, y),
        Offset(size.width, y),
        tickPaint,
      );
    }

    // 绘制右侧竖线
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      tickPaint,
    );
  }

  /// 根据缩放级别获取刻度间隔（毫秒）
  (int major, int minor) _getIntervals(double pixelsPerSecond) {
    if (pixelsPerSecond >= 0.05) {
      // 很详细：每10秒主刻度，每1秒次刻度
      return (10000, 1000);
    } else if (pixelsPerSecond >= 0.02) {
      // 详细：每30秒主刻度，每5秒次刻度
      return (30000, 5000);
    } else if (pixelsPerSecond >= 0.01) {
      // 正常：每1分钟主刻度，每10秒次刻度
      return (60000, 10000);
    } else if (pixelsPerSecond >= 0.005) {
      // 紧凑：每2分钟主刻度，每30秒次刻度
      return (120000, 30000);
    } else {
      // 很紧凑：每5分钟主刻度，每1分钟次刻度
      return (300000, 60000);
    }
  }

  /// 格式化时间（毫秒 → MM:SS 或 HH:MM:SS）
  String _formatTime(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalRulerPainter oldDelegate) {
    return oldDelegate.scrollOffsetMs != scrollOffsetMs ||
        oldDelegate.viewportHeight != viewportHeight ||
        oldDelegate.pixelsPerMs != pixelsPerMs;
  }
}
