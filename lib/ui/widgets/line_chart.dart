/// 月度资产变化折线图（自绘，无第三方图表库）
library;

import 'package:material_ui/material_ui.dart';

import '../../services/format.dart';
import '../../store/app_store.dart';
import '../theme.dart';

/// 按月累计净投入折线图
class AssetTrendChart extends StatelessWidget {
  const AssetTrendChart({super.key, required this.points, this.height = 190});

  final List<AssetMonthPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    if (points.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '数据积累中：至少需要两个月的记录才能绘制曲线',
          style: TextStyle(fontSize: 12.5, color: gc.muted),
          textAlign: TextAlign.center,
        ),
      );
    }

    final values = points.map((p) => p.cumulativeInvested).toList();
    final hi = values.fold<double>(1, (m, v) => v > m ? v : m);
    final lo = values.fold<double>(0, (m, v) => v < m ? v : m);
    final latest = values.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('当前净投入', style: TextStyle(fontSize: 11, color: gc.muted2)),
            Text(
              money(latest),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: gc.primary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _TrendPainter(
              values: values,
              hi: hi,
              lo: lo,
              lineColor: gc.primary,
              areaColor: gc.primary.withValues(alpha: 0.14),
              dotColor: gc.primary,
              axisColor: gc.line,
              zeroColor: gc.muted2,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(points.first.month, style: TextStyle(fontSize: 10.5, color: gc.muted2)),
            if (points.length > 2)
              Text(points[points.length ~/ 2].month, style: TextStyle(fontSize: 10.5, color: gc.muted2)),
            Text(points.last.month, style: TextStyle(fontSize: 10.5, color: gc.muted2)),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.hi,
    required this.lo,
    required this.lineColor,
    required this.areaColor,
    required this.dotColor,
    required this.axisColor,
    required this.zeroColor,
  });

  final List<double> values;
  final double hi;
  final double lo;
  final Color lineColor;
  final Color areaColor;
  final Color dotColor;
  final Color axisColor;
  final Color zeroColor;

  @override
  void paint(Canvas canvas, Size size) {
    const l = 6.0;
    const r = 6.0;
    const t = 8.0;
    const b = 8.0;
    final chartW = size.width - l - r;
    final chartH = size.height - t - b;
    final n = values.length;
    if (n < 2 || chartW <= 0 || chartH <= 0) return;

    Offset pos(int i) {
      final x = l + chartW * i / (n - 1);
      final v = values[i];
      final y = t + (hi - v) / (hi - lo) * chartH;
      return Offset(x, y);
    }

    // 零值基线（回收超过购入时曲线可能低于 0）
    final zeroY = t + (hi - 0) / (hi - lo) * chartH;
    canvas.drawLine(
      Offset(l, zeroY),
      Offset(size.width - r, zeroY),
      Paint()
        ..color = zeroColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    final path = Path()..moveTo(pos(0).dx, pos(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(pos(i).dx, pos(i).dy);
    }

    // 区域填充
    final area = Path.from(path)
      ..lineTo(pos(n - 1).dx, zeroY)
      ..lineTo(pos(0).dx, zeroY)
      ..close();
    canvas.drawPath(area, Paint()..color = areaColor);

    // 折线
    canvas.drawPath(path, Paint()..color = lineColor..strokeWidth = 2..strokeCap = StrokeCap.round);

    // 数据点（首尾必画，中间隔点抽稀）
    final dotPaint = Paint()..color = dotColor;
    for (var i = 0; i < n; i++) {
      if (n > 24 && i % 2 == 1 && i != n - 1) continue;
      canvas.drawCircle(pos(i), i == n - 1 ? 4 : 2.6, dotPaint);
    }
    canvas.drawCircle(pos(n - 1), 6, Paint()..color = dotColor.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.hi != hi ||
      oldDelegate.lo != lo ||
      oldDelegate.lineColor != lineColor;
}
