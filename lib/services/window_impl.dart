/// 桌面端实现：窗口尺寸/位置持久化
///
/// 使用 window_manager 0.7 的 legacy 兼容 API（单窗口场景足够；
/// 新的多窗口实验 API 需要开启 Flutter 实验特性，暂不采用）。
// ignore_for_file: deprecated_member_use
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset, Size;

import 'package:window_manager/legacy.dart';

/// 恢复上次窗口尺寸/位置（无记录时使用默认值），并挂载自动保存监听
Future<void> initDesktopWindow(
  Future<void> Function(String json) save,
  String Function() load,
) async {
  await windowManager.ensureInitialized();

  Size? size;
  Offset? position;
  final raw = load();
  if (raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final w = (decoded['w'] as num?)?.toDouble();
      final h = (decoded['h'] as num?)?.toDouble();
      final x = (decoded['x'] as num?)?.toDouble();
      final y = (decoded['y'] as num?)?.toDouble();
      if (w != null && h != null && w > 200 && h > 200) size = Size(w, h);
      if (x != null && y != null) position = Offset(x, y);
    } catch (_) {
      // 记录损坏则使用默认值
    }
  }

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: size ?? const Size(1280, 820),
      minimumSize: const Size(960, 640),
      center: position == null,
      title: '物盒册',
    ),
    () async {
      await windowManager.show();
      if (position != null) {
        await windowManager.setBounds(null, position: position, size: size);
      }
      await windowManager.focus();
    },
  );

  windowManager.addListener(_WindowSaver(save));
}

class _WindowSaver extends WindowListener {
  _WindowSaver(this.onSave);

  final Future<void> Function(String json) onSave;
  Timer? _timer;

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final size = await windowManager.getSize();
        final position = await windowManager.getPosition();
        await onSave(jsonEncode({
          'w': size.width,
          'h': size.height,
          'x': position.dx,
          'y': position.dy,
        }));
      } catch (_) {
        // 窗口关闭瞬间的取值失败可以忽略
      }
    });
  }

  @override
  void onWindowResize() => _schedule();

  @override
  void onWindowResized() => _schedule();

  @override
  void onWindowMove() => _schedule();

  @override
  void onWindowMoved() => _schedule();
}
