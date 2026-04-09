import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 全屏图片查看组件
///
/// 使用 [InteractiveViewer] 实现缩放和平移功能。
/// 通过 [showImageViewer] 便捷方法以全屏对话框方式展示。
/// Author: GDNDZZK
class ImageViewer extends StatelessWidget {
  /// 图片二进制数据
  final Uint8List imageData;

  /// 图片描述（可选）
  final String? description;

  const ImageViewer({
    super.key,
    required this.imageData,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: description != null
            ? Text(
                description!,
                style: const TextStyle(fontSize: 14),
              )
            : null,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            imageData,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image,
                    size: 64,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 以全屏方式展示图片查看器
///
/// [context] BuildContext
/// [imageData] 图片二进制数据
/// [description] 图片描述（可选）
///
/// Author: GDNDZZK
Future<void> showImageViewer(
  BuildContext context, {
  required Uint8List imageData,
  String? description,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ImageViewer(
        imageData: imageData,
        description: description,
      ),
    ),
  );
}
