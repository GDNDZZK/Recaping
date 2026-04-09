import 'dart:ui' as ui;
import 'dart:typed_data';

/// 图片缩略图生成工具
///
/// 使用 dart:ui 的 [ui.instantiateImageCodec] 解码图片并生成缩略图。
/// Author: GDNDZZK
class ThumbnailUtil {
  ThumbnailUtil._();

  /// 生成缩略图
  ///
  /// [imageData] 原始图片数据
  /// [maxSize] 缩略图最大边长（像素），默认 200
  ///
  /// 返回 PNG 格式的缩略图数据
  static Future<Uint8List> generate(
    Uint8List imageData, {
    int maxSize = 200,
  }) async {
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // 计算缩略图尺寸，保持宽高比
    final ratio = image.width / image.height;
    int thumbWidth;
    int thumbHeight;
    if (ratio > 1) {
      thumbWidth = maxSize;
      thumbHeight = (maxSize / ratio).round();
    } else {
      thumbHeight = maxSize;
      thumbWidth = (maxSize * ratio).round();
    }

    // 确保尺寸至少为 1
    thumbWidth = thumbWidth.clamp(1, maxSize);
    thumbHeight = thumbHeight.clamp(1, maxSize);

    // 使用 PictureRecorder 重新绘制缩略图
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, thumbWidth.toDouble(), thumbHeight.toDouble()),
      paint,
    );

    final picture = recorder.endRecording();
    final thumbnail = await picture.toImage(thumbWidth, thumbHeight);
    final byteData = await thumbnail.toByteData(
      format: ui.ImageByteFormat.png,
    );

    // 释放资源
    image.dispose();
    thumbnail.dispose();

    return byteData!.buffer.asUint8List();
  }
}
