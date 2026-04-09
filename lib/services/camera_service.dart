import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 拍照结果
class CameraResult {
  /// 图片数据
  final Uint8List data;

  /// 图片宽度（像素）
  final int width;

  /// 图片高度（像素）
  final int height;

  const CameraResult({
    required this.data,
    required this.width,
    required this.height,
  });
}

/// 录像结果
class VideoResult {
  /// 视频数据
  final Uint8List data;

  const VideoResult({required this.data});
}

/// 相机服务
///
/// 封装 [ImagePicker] 提供拍照、录像和从相册选择图片的功能。
/// Author: GDNDZZK
class CameraService {
  final ImagePicker _picker = ImagePicker();

  /// 拍照，返回图片数据
  ///
  /// 用户取消操作时返回 null。
  /// 不设置 maxWidth/maxHeight/imageQuality，保留原图质量。
  Future<CameraResult?> takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    // 注意：图片尺寸需要通过解码获取，这里返回 0，
    // 实际尺寸由调用方（如 TimelineService）在需要时获取
    return CameraResult(data: bytes, width: 0, height: 0);
  }

  /// 录制视频，返回视频数据
  ///
  /// 用户取消操作时返回 null。
  /// 视频最大时长 5 分钟。
  Future<VideoResult?> recordVideo() async {
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5),
    );
    if (video == null) return null;

    final bytes = await video.readAsBytes();
    return VideoResult(data: bytes);
  }

  /// 从相册选择图片
  ///
  /// 用户取消操作时返回 null。
  /// 不设置 maxWidth/maxHeight/imageQuality，保留原图质量。
  Future<CameraResult?> pickFromGallery() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    return CameraResult(data: bytes, width: 0, height: 0);
  }
}
