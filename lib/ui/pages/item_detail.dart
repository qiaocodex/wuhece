/// 物品详情（对应 Web 版 items.js 的 openItemDetail）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/dates.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_form.dart';

/// 打开物品详情（宽屏对话框 / 窄屏底部面板）
Future<void> openItemDetail(BuildContext context, String itemId) {
  return showResponsive<void>(
    context,
    maxWidth: 640,
    builder: (_) => _ItemDetailBody(itemId: itemId),
  );
}

class _ItemDetailBody extends StatelessWidget {
  const _ItemDetailBody({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final item = store.getItem(itemId);
        if (item == null) {
          // 物品已被删除：关闭弹层
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        return FormScaffold(
          title: '物品详情',
          body: _content(context, store, item),
          actions: _actions(context, store, item),
        );
      },
    );
  }

  Widget _content(BuildContext context, AppStore store, Item item) {
    final cat = store.getCategory(item.categoryId);
    final catColor = hexToColor(cat?.color);
    final catName = cat?.name ?? '未分类';
    final end = store.warrantyEnd(item);
    final lastDays = store.daysSinceLastUse(item);
    final logs = item.logs.take(8).toList();
    const logLabel = {'use': '记录使用', 'lend': '借出', 'return': '归还'};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(item, catColor),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GColors.ink),
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(status: item.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$catName · ${store.spacePathLabel(item.spaceId)}',
          style: const TextStyle(fontSize: 12.5, color: GColors.muted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metaCell('数量', '${item.quantity} 件'),
            _metaCell('单价 / 总价值', '${money(item.price)} / ${money(item.value)}'),
            _metaCell('购入日期', formatDate(item.purchaseDate)),
            _metaCell('保修截止', end != null ? formatDate(end) : '无保修信息'),
            _metaCell('最近使用', lastDays == 0 ? '今天' : '$lastDays 天前'),
            _metaCell('录入时间', formatDate(item.createdAt)),
          ],
        ),
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel('标签'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in item.tags) TagChip(text: t)]),
        ],
        if (item.note.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel('备注'),
          const SizedBox(height: 6),
          Text(
            item.note,
            style: const TextStyle(fontSize: 13, color: GColors.inkSoft, height: 1.7),
          ),
        ],
        const SizedBox(height: 14),
        const _SectionLabel('使用记录'),
        const SizedBox(height: 6),
        if (logs.isEmpty)
          const Text(
            '还没有使用记录，记录一次可以帮助你判断物品的真实使用频率。',
            style: TextStyle(fontSize: 12.5, color: GColors.muted),
          )
        else
          for (final log in logs) _logRow(log, logLabel[log.type] ?? '记录'),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _hero(Item item, Color catColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 150,
        color: item.image != null ? Colors.black : catColor.withValues(alpha: 0.07),
        child: item.image != null
            ? ItemThumb(image: item.image, color: catColor, size: double.infinity, iconSize: 44)
            : Icon(Icons.inventory_2_outlined, size: 44, color: catColor),
      ),
    );
  }

  Widget _metaCell(String label, String value) {
    return Container(
      width: 236,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: GColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: GColors.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _logRow(UsageLog log, String label) {
    final dotColor = switch (log.type) {
      'lend' => GColors.blue,
      'return' => GColors.amber,
      _ => GColors.primary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.note.isEmpty ? label : '$label · ${log.note}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: GColors.ink),
                ),
                Text(formatDateTime(log.at), style: const TextStyle(fontSize: 11, color: GColors.muted2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, AppStore store, Item item) {
    return [
      FilledButton.icon(
        onPressed: () {
          store.logUsage(item.id, type: 'use');
          toast(context, '已记录一次使用');
        },
        icon: const Icon(Icons.check, size: 14),
        label: const Text('记一次使用'),
      ),
      if (item.status == 'lent')
        OutlinedButton.icon(
          onPressed: () {
            store.logUsage(item.id, type: 'return');
            toast(context, '已登记归还');
          },
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('登记归还'),
        )
      else
        OutlinedButton.icon(
          onPressed: () {
            store.logUsage(item.id, type: 'lend');
            toast(context, '已标记为借出');
          },
          icon: const Icon(Icons.arrow_forward, size: 14),
          label: const Text('标记借出'),
        ),
      OutlinedButton(
        onPressed: () {
          Navigator.pop(context);
          openItemForm(context, item);
        },
        child: const Text('编辑'),
      ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: GColors.danger,
          side: const BorderSide(color: GColors.dangerWeak),
        ),
        onPressed: () async {
          final ok = await confirmDialog(
            context,
            title: '删除物品',
            message: '确定删除「${item.name}」吗？相关的使用记录也会一并删除，此操作不可撤销。',
            confirmText: '删除',
            danger: true,
          );
          if (!ok || !context.mounted) return;
          Navigator.pop(context);
          store.deleteItem(item.id);
          toast(context, '物品已删除');
        },
        child: const Text('删除'),
      ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GColors.ink),
    );
  }
}
