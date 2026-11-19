/// 生成应用图标与启动屏素材（立方体线框 logo，与 Web 版 favicon 同一设计）。
/// 运行：dart run tool/generate_assets.dart
library;

import 'dart:io';

import 'package:image/image.dart' as img;

const int size = 1024;
const double lineWidth = 54; // 32 空间线宽 1.7 × 32 倍

/// 32 空间的立方体顶点（favicon 设计）
const List<List<double>> hexagon = [
  [9, 12.5], [16, 9], [23, 12.5], [23, 19.5], [16, 23], [9, 19.5],
];
const List<List<double>> innerLines = [
  [9, 12.5, 16, 16],
  [16, 16, 23, 12.5],
  [16, 16, 16, 23],
];

img.Image newCanvas({required img.ColorRgb8 background}) {
  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: background);
  return canvas;
}

/// 在画布中央绘制缩放后的白色立方体线框
void drawCube(img.Image canvas, {required double scaleFactor, required img.ColorRgb8 color, bool roundedJoints = true}) {
  double m(double v) => size / 2 + (v - 16) * 32 * scaleFactor;
  final w = (lineWidth * scaleFactor).round().clamp(2, size);

  final pts = hexagon.map((p) => [m(p[0]), m(p[1])]).toList();
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    img.drawLine(
      canvas,
      x1: a[0].round(),
      y1: a[1].round(),
      x2: b[0].round(),
      y2: b[1].round(),
      color: color,
      thickness: w,
    );
  }
  for (final l in innerLines) {
    img.drawLine(
      canvas,
      x1: m(l[0]).round(),
      y1: m(l[1]).round(),
      x2: m(l[2]).round(),
      y2: m(l[3]).round(),
      color: color,
      thickness: w,
    );
  }
  if (roundedJoints) {
    // 顶点处画实心圆做圆角接头
    final r = (w / 2).round();
    for (final p in pts) {
      img.fillCircle(canvas, x: p[0].round(), y: p[1].round(), radius: r, color: color);
    }
    for (final l in innerLines) {
      img.fillCircle(canvas, x: m(l[0]).round(), y: m(l[1]).round(), radius: r, color: color);
      img.fillCircle(canvas, x: m(l[2]).round(), y: m(l[3]).round(), radius: r, color: color);
    }
  }
}

void main() {
  Directory('assets/icons').createSync(recursive: true);
  final green = img.ColorRgb8(0x2E, 0x6B, 0x5E);
  final white = img.ColorRgb8(255, 255, 255);

  // 传统图标：绿底 + 白色立方体（iOS / 旧版 Android / Web favicon / Windows）
  final legacy = newCanvas(background: green);
  drawCube(legacy, scaleFactor: 1.0, color: white);
  img.encodePngFile('assets/icons/icon-legacy.png', legacy);
  stdout.writeln('✔ assets/icons/icon-legacy.png');

  // Android 自适应图标前景：透明底 + 立方体缩小到 62%（四周留安全边距）
  final foreground = img.Image(width: size, height: size);
  drawCube(foreground, scaleFactor: 0.62, color: white);
  img.encodePngFile('assets/icons/icon-foreground.png', foreground);
  stdout.writeln('✔ assets/icons/icon-foreground.png');

  // 启动屏 logo：透明底白色立方体（splash 用 512 尺寸即可）
  final splash = img.Image(width: 512, height: 512);
  final half = img.copyResize(
    (() {
      final c = img.Image(width: size, height: size);
      drawCube(c, scaleFactor: 0.62, color: white);
      return c;
    })(),
    width: 512,
  );
  img.compositeImage(splash, half);
  img.encodePngFile('assets/icons/splash-logo.png', splash);
  stdout.writeln('✔ assets/icons/splash-logo.png');
}
