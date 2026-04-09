import 'dart:math';

import 'package:flutter/material.dart';

/// 音频波形动画指示器
///
/// 录音时显示跳动的波形条，暂停时波形静止。
/// 使用多个竖条 + 随机高度变化模拟波形效果。
/// Author: GDNDZZK
class WaveformIndicator extends StatefulWidget {
  /// 是否激活（录音中）
  final bool isActive;

  /// 波形条颜色
  final Color color;

  /// 波形条数量，默认 20
  final int barCount;

  const WaveformIndicator({
    super.key,
    required this.isActive,
    this.color = const Color(0xFFFF4444),
    this.barCount = 20,
  });

  @override
  State<WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<WaveformIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final _random = Random();

  /// 每个波形条的目标高度（0.0 ~ 1.0）
  late List<double> _targetHeights;

  /// 每个波形条的当前高度（0.0 ~ 1.0）
  late List<double> _currentHeights;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _targetHeights = List.generate(widget.barCount, (_) => 0.2);
    _currentHeights = List.generate(widget.barCount, (_) => 0.2);

    _controller.addListener(_updateHeights);

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(WaveformIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      // 暂停时将高度重置为较低值
      setState(() {
        for (int i = 0; i < widget.barCount; i++) {
          _currentHeights[i] = 0.15;
          _targetHeights[i] = 0.15;
        }
      });
    }
  }

  /// 更新波形条高度
  void _updateHeights() {
    setState(() {
      for (int i = 0; i < widget.barCount; i++) {
        // 平滑过渡到目标高度
        _currentHeights[i] +=
            (_targetHeights[i] - _currentHeights[i]) * 0.3;
      }
    });

    // 每次动画循环结束时生成新的目标高度
    if (_controller.status == AnimationStatus.completed) {
      for (int i = 0; i < widget.barCount; i++) {
        _targetHeights[i] = 0.15 + _random.nextDouble() * 0.85;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        heights: _currentHeights,
        color: widget.color,
        isActive: widget.isActive,
      ),
      size: Size(
        widget.barCount * 6.0,
        32.0,
      ),
    );
  }
}

/// 波形绘制器
///
/// 绘制多个竖条，高度由 [heights] 列表决定。
/// Author: GDNDZZK
class _WaveformPainter extends CustomPainter {
  final List<double> heights;
  final Color color;
  final bool isActive;

  _WaveformPainter({
    required this.heights,
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: isActive ? 0.8 : 0.3)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / heights.length;
    const barRadius = 1.5;

    for (int i = 0; i < heights.length; i++) {
      final barHeight = heights[i] * size.height;
      final x = i * barWidth + barWidth * 0.15;
      final barW = barWidth * 0.7;
      final y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, barHeight),
        const Radius.circular(barRadius),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return true; // 持续重绘以实现动画效果
  }
}
