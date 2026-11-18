/// 图片服务：选图 + 统一压缩管线（对应 Web 版 compressImage）
///
/// 四端共用一条管线：dart:ui 解码 → 缩放（最长边 ≤900）→ 白底压平 →
/// JPEG(质量 72) → base64 dataURL，直接跟随数据存入本地，与 Web 版一致。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 打开选图入口并返回压缩后的 dataURL（取消或失败返回 null）
Future<String?> pickImageAsDataUrl(BuildContext context) async {
  try {
    Uint8List? bytes;
    if (kIsWeb) {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return null;
      bytes = await picked.readAsBytes();
    } else if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final source = await _chooseMobileSource(context);
      if (source == null) return null;
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return null;
      bytes = await picked.readAsBytes();
    } else {
      const group = XTypeGroup(
        label: '图片',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      );
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null) return null;
      bytes = await file.readAsBytes();
    }
    if (bytes.isEmpty) return null;
    return await compressToDataUrl(bytes);
  } catch (err) {
    debugPrint('选图失败：$err');
    return null;
  }
}

/// 移动端：拍照 / 相册 选择
Future<ImageSource?> _chooseMobileSource(BuildContext context) async {
  ImageSource? source;
  await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  return source;
}

/// 压缩为 dataURL：最长边 900px、JPEG 质量 72、白底压平
Future<String?> compressToDataUrl(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;

    const maxDim = 900;
    final scale = min(1.0, maxDim / max(src.width, src.height));
    final w = max(1, (src.width * scale).round());
    final h = max(1, (src.height * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final scaled = await recorder.endRecording().toImage(w, h);
    final data = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);

    src.dispose();
    scaled.dispose();
    codec.dispose();

    if (data == null) return null;
    final rgba = data.buffer.asUint8List();

    // 白底压平后编码 JPEG（JPEG 不支持透明通道）
    final decoded = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final flattened = img.Image(width: w, height: h);
    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, decoded);
    final jpeg = img.encodeJpg(flattened, quality: 72);
    return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
  } catch (err) {
    debugPrint('图片压缩失败：$err');
    return null;
  }
}
