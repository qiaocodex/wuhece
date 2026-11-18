/// 通用 UI 组件（对应 Web 版 components.js）
library;

import 'dart:convert';
import 'dart:math' show pi;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import 'theme.dart';

/* ------------------------- 布局 ------------------------- */

/// 页面内容统一宽度与内边距
Widget pageContainer(BuildContext context, {required List<Widget> children}) {
  final wide = isWide(context);
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 26 : 18, wide ? 28 : 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// 页头：标题 + 副标题 + 右侧操作区
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.sub, this.actions = const []});

  final String title;
  final String sub;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final actionRow = actions.isEmpty
        ? const SizedBox.shrink()
        : Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 3),
              Text(sub, style: const TextStyle(fontSize: 13, color: GColors.muted)),
            ],
          ),
          actionRow,
        ],
      ),
    );
  }
}

/// 卡片容器（白底、16 圆角、轻阴影）
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0A2C261E), blurRadius: 6, offset: Offset(0, 2)),
          BoxShadow(color: Color(0x082C261E), blurRadius: 1, offset: Offset(0, 1)),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 带标题的分区卡片
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.sub,
    this.action,
    required this.child,
    this.footer,
  });

  final String title;
  final String? sub;
  final Widget? action;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub!, style: const TextStyle(fontSize: 12, color: GColors.muted)),
                    ],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 14),
          child,
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// 统计卡片
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueSuffix,
    this.hint,
    this.iconBg = GColors.primaryWeak,
    this.iconColor = GColors.primary,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? valueSuffix;
  final String? hint;
  final Color iconBg;
  final Color iconColor;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(),
              if (badge != null) ...[
                const Spacer(),
                Text(badge!, style: const TextStyle(fontSize: 11, color: GColors.muted)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 12, color: GColors.muted)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: GColors.ink, height: 1.15),
              ),
              if (valueSuffix != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(valueSuffix!,
                      style: const TextStyle(fontSize: 11.5, color: GColors.muted, fontWeight: FontWeight.w500)),
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: GColors.muted2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconBox() => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: iconColor),
      );
}

/// 响应式统计卡网格：宽屏一行 4 个，窄屏 2×2
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

/* ------------------------- 数据展示 ------------------------- */

/// 进度条行（名称 + 数值 + 横条）
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.name,
    required this.valueText,
    this.pct,
    this.color,
    this.leading,
  });

  final String name;
  final String valueText;

  /// 0-100，null 表示未设置
  final int? pct;
  final Color? color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final double p = pct == null ? 0.0 : pct!.clamp(0, 100).toDouble() / 100;
    final fill = color ??
        (pct != null && pct! >= 100
            ? GColors.danger
            : pct != null && pct! >= 90
                ? GColors.amber
                : GColors.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: GColors.inkSoft),
                ),
              ),
              const SizedBox(width: 8),
              Text(valueText, style: const TextStyle(fontSize: 12, color: GColors.muted)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 7,
              backgroundColor: GColors.bgDeep,
              valueColor: AlwaysStoppedAnimation(fill),
            ),
          ),
        ],
      ),
    );
  }
}

class DonutSegment {
  const DonutSegment({required this.value, required this.color});
  final double value;
  final Color color;
}

/// 环形图（自定义绘制，对应 Web 版 donutHTML）
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    required this.centerTitle,
    this.centerSub = '',
    this.size = 150,
    this.strokeWidth = 26,
  });

  final List<DonutSegment> segments;
  final String centerTitle;
  final String centerSub;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
              segments: segments.where((s) => s.value > 0).toList(),
              strokeWidth: strokeWidth,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GColors.ink),
              ),
              if (centerSub.isNotEmpty)
                Text(centerSub, style: const TextStyle(fontSize: 11, color: GColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.strokeWidth});

  final List<DonutSegment> segments;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inner = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width - strokeWidth,
      height: size.height - strokeWidth,
    );
    if (segments.isEmpty) {
      canvas.drawArc(inner, 0, 2 * pi, true, Paint()..color = GColors.bgDeep);
      return;
    }
    final total = segments.fold(0.0, (s, seg) => s + seg.value);
    if (total <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    var start = -pi / 2;
    for (final seg in segments) {
      final sweep = seg.value / total * 2 * pi;
      paint.color = seg.color;
      canvas.drawArc(inner, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.strokeWidth != strokeWidth;
}

/// 图例列表
class LegendList extends StatelessWidget {
  const LegendList({super.key, required this.rows});

  final List<LegendRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: r.color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: GColors.inkSoft),
                  ),
                ),
                Text(r.value, style: const TextStyle(fontSize: 12, color: GColors.muted)),
              ],
            ),
          ),
      ],
    );
  }
}

class LegendRow {
  const LegendRow({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;
}

/* ------------------------- 徽章 / 标签 ------------------------- */

/// 物品状态徽章
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final meta = kStatusMeta[status] ?? kStatusMeta['in_use']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: toneWeakColor(meta.tone), borderRadius: BorderRadius.circular(999)),
      child: Text(
        meta.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: toneColor(meta.tone)),
      ),
    );
  }
}

/// 通用小徽章
class MiniBadge extends StatelessWidget {
  const MiniBadge({super.key, required this.label, this.color = GColors.primary, this.bg = GColors.primaryWeak});

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// 标签 chip
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: GColors.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GColors.line),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: GColors.muted)),
    );
  }
}

/// 筛选圆形 chip（分类/建议过滤器）
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.active, required this.onTap, this.dotColor});

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? GColors.primary : GColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? GColors.primary : GColors.lineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Colors.white : GColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------- 空态 ------------------------- */

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.desc, this.action});

  final IconData icon;
  final String title;
  final String? desc;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: GColors.surfaceSoft, shape: BoxShape.circle, border: Border.all(color: GColors.line)),
            child: Icon(icon, size: 22, color: GColors.muted),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GColors.ink)),
          if (desc != null) ...[
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                desc!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: GColors.muted, height: 1.6),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

/* ------------------------- 图片 ------------------------- */

/// 物品缩略图：dataURL 解码缓存，无图时用分类色占位
class ItemThumb extends StatefulWidget {
  const ItemThumb({
    super.key,
    required this.image,
    required this.color,
    this.size = 40,
    this.iconSize = 16,
    this.fill = false,
  });

  final String? image;
  final Color color;
  final double size;
  final double iconSize;

  /// true：图片铺满父容器（卡片头图模式）
  final bool fill;

  @override
  State<ItemThumb> createState() => _ItemThumbState();
}

class _ItemThumbState extends State<ItemThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant ItemThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _decode();
  }

  void _decode() {
    final src = widget.image;
    if (src == null || src.isEmpty) {
      _bytes = null;
      return;
    }
    final i = src.indexOf('base64,');
    try {
      _bytes = i >= 0 ? base64Decode(src.substring(i + 7)) : base64Decode(src);
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      final image = Image.memory(
        _bytes!,
        width: widget.fill ? double.infinity : widget.size,
        height: widget.fill ? double.infinity : widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
      return widget.fill ? image : ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
    }
    return Container(
      width: widget.fill ? double.infinity : widget.size,
      height: widget.fill ? double.infinity : widget.size,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.inventory_2_outlined, size: widget.iconSize, color: widget.color),
    );
  }
}

/* ------------------------- 弹层与提示 ------------------------- */

/// 轻提示（对应 Web 版 toast）
void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: error ? GColors.danger : GColors.ink,
      duration: const Duration(milliseconds: 2200),
    ));
}

/// 响应式弹层：宽屏居中对话框，窄屏底部面板
Future<T?> showResponsive<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 560,
}) {
  final size = MediaQuery.sizeOf(context);
  if (isFormWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: size.height * 0.9),
          child: ClipRRect(borderRadius: BorderRadius.circular(20), child: builder(ctx)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.95),
      decoration: const BoxDecoration(
        color: GColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: builder(ctx),
    ),
  );
}

/// 表单弹层骨架：标题栏 + 滚动内容 + 底部按钮
class FormScaffold extends StatelessWidget {
  const FormScaffold({super.key, required this.title, required this.body, this.actions = const []});

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: GColors.muted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 18), child: body)),
          if (actions.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 确认对话框（对应 Web 版 confirmDialog）
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确认',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text(
        message,
        style: const TextStyle(fontSize: 13, color: GColors.inkSoft, height: 1.6),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger ? FilledButton.styleFrom(backgroundColor: GColors.danger) : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 表单字段：标签 + 控件（对应 Web 版 .field）
class FormField2 extends StatelessWidget {
  const FormField2({super.key, required this.label, required this.child, this.fullWidth = false, this.hint});

  final String label;
  final Widget child;
  final bool fullWidth;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GColors.inkSoft),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: const TextStyle(fontSize: 11, color: GColors.muted2)),
        ],
      ],
    );
  }
}

/// 表单字段网格：宽屏两列，窄屏单列
class FormGrid extends StatelessWidget {
  const FormGrid({super.key, required this.children, this.fullWidths = const []});

  /// 与 children 等长的"是否占满整行"标记
  final List<bool> fullWidths;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final twoCols = isFormWide(context);
    if (!twoCols) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < children.length; i++) ...[Padding(padding: const EdgeInsets.only(bottom: 14), child: children[i])]],
      );
    }
    final rows = <Widget>[];
    var row = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final full = i < fullWidths.length ? fullWidths[i] : false;
      row.add(Expanded(flex: full ? 2 : 1, child: Padding(padding: const EdgeInsets.only(right: 12, bottom: 14), child: children[i])));
      if (full || row.length == 2) {
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: row));
        row = <Widget>[];
      }
    }
    if (row.isNotEmpty) rows.add(Row(children: row));
    return Column(children: rows);
  }
}

/* ------------------------- 通用小组件 ------------------------- */

/// 下拉选择（统一样式）
class SelectField<T> extends StatelessWidget {
  const SelectField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: GColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GColors.lineStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: hint == null ? null : Text(hint!, style: const TextStyle(fontSize: 13.5)),
          isExpanded: true,
          dropdownColor: GColors.surface,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.expand_more, size: 18, color: GColors.muted),
          style: const TextStyle(fontSize: 13.5, color: GColors.ink),
        ),
      ),
    );
  }
}

/// 页面卡片间的纵向间距
const double kSectionGap = 18;

/// 宽屏两列并排，窄屏上下堆叠（对应 Web 版 grid-2）
Widget twoColumns(BuildContext context, Widget left, Widget right, {double gap = 18}) {
  if (isWide(context)) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );
  }
  return Column(children: [left, SizedBox(height: gap), right]);
}
