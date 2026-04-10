import 'dart:math';

import 'package:flutter/material.dart';

/// 音频波形动画指示器
///
/// 录音时显示跳动的波形条，暂停时波形静止。
/// 使用多个竖条显示真实音频振幅数据。
/// Author: GDNDZZK
class WaveformIndicator extends StatefulWidget {
  /// 是否激活（录音中）
  final bool isActive;

  /// 波形条颜色
  final Color color;

  /// 波形条数量，默认 20
  final int barCount;

  /// 当前振幅高度（0.0 ~ 1.0），来自真实音频数据
  final double amplitude;

  const WaveformIndicator({
    super.key,
    required this.isActive,
    this.color = const Color(0xFFFF4444),
    this.barCount = 20,
    this.amplitude = 0.0,
  });

  @override
  State<WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<WaveformIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// 每个波形条的当前高度（0.0 ~ 1.0）
  late List<double> _currentHeights;

  /// 每个波形条的目标高度（0.0 ~ 1.0）
  late List<double> _targetHeights;

  /// 上一次的振幅值，用于平滑过渡
  double _lastAmplitude = 0.0;

  /// 随机数生成器，用于生成波形变化
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _currentHeights = List.generate(widget.barCount, (_) => 0.15);
    _targetHeights = List.generate(widget.barCount, (_) => 0.15);

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

    // 当振幅值变化时，更新目标高度
    if (widget.amplitude != _lastAmplitude) {
      _updateTargetHeights(widget.amplitude);
      _lastAmplitude = widget.amplitude;
    }
  }

  /// 根据振幅值更新目标高度
  ///
  /// [amplitude] 是 0.0 ~ 1.0 的归一化振幅值
  void _updateTargetHeights(double amplitude) {
    // 基于振幅值生成波形高度
    // 中间的条高度更接近振幅值，两侧的条高度逐渐降低
    final centerIndex = widget.barCount ~/ 2;
    
    for (int i = 0; i < widget.barCount; i++) {
      // 计算距离中心的距离（0.0 ~ 1.0）
      final distanceFromCenter = (i - centerIndex).abs() / (centerIndex + 1);
      
      // 添加随机变化，使波形更自然
      final randomFactor = 0.7 + _random.nextDouble() * 0.6; // 0.7 ~ 1.3
      
      // 根据振幅和位置计算高度
      // 中心位置的高度更接近振幅值，两侧逐渐降低
      final baseHeight = amplitude * (1.0 - distanceFromCenter * 0.5) * randomFactor;
      
      // 确保最小高度为 0.1，最大高度为 1.0
      _targetHeights[i] = baseHeight.clamp(0.1, 1.0);
    }
  }

  /// 更新波形条高度
  void _updateHeights() {
    setState(() {
      for (int i = 0; i < widget.barCount; i++) {
        // 平滑过渡到目标高度（使用 lerp 实现平滑动画）
        _currentHeights[i] = _lerp(_currentHeights[i], _targetHeights[i], 0.3);
      }
    });
  }

  /// 线性插值
  double _lerp(double current, double target, double t) {
    return current + (target - current) * t;
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
