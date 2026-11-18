/// 整理建议（对应 Web 版 insights.js）
library;

import 'package:material_ui/material_ui.dart';

import '../../store/app_store.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_detail.dart';
import 'space_form.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  String _filter = 'all';

  IconData _typeIcon(String type) => switch (type) {
        'idle' => Icons.schedule,
        'warranty' => Icons.verified_user_outlined,
        'duplicate' => Icons.layers_outlined,
        'space' => Icons.inventory_2_outlined,
        'lent' => Icons.arrow_forward,
        'unplaced' => Icons.push_pin_outlined,
        _ => Icons.lightbulb_outlined,
      };

  (Color, Color) _severityColors(String severity) => switch (severity) {
        'high' => (GColors.danger, GColors.dangerWeak),
        'medium' => (GColors.amber, GColors.amberWeak),
        _ => (GColors.blue, GColors.blueWeak),
      };

  String _severityLabel(String severity) => switch (severity) {
        'high' => '优先处理',
        'medium' => '建议整理',
        _ => '可以关注',
      };

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.getSuggestions();
        final high = all.where((s) => s.severity == 'high').length;
        final medium = all.where((s) => s.severity == 'medium').length;
        final low = all.where((s) => s.severity == 'low').length;
        final list = _filter == 'all' ? all : all.where((s) => s.severity == _filter).toList();

        return pageContainer(
          context,
          children: [
            PageHeader(
              title: '整理建议',
              sub: '根据使用记录、保修期限与空间利用率自动生成',
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {});
                    toast(context, '已重新分析');
                  },
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('重新分析'),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', '全部 ${all.length}'),
                  const SizedBox(width: 8),
                  _filterChip('high', '优先处理 $high'),
                  const SizedBox(width: 8),
                  _filterChip('medium', '建议整理 $medium'),
                  const SizedBox(width: 8),
                  _filterChip('low', '可以关注 $low'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              EmptyState(
                icon: Icons.check_circle_outline,
                title: all.isEmpty ? '空间和物品都很健康' : '这个分组暂时没有建议',
                desc: all.isEmpty
                    ? '继续记录使用情况，系统会持续给出更精准的整理建议。'
                    : '切换到其他优先级看看，或稍后再来检查。',
              )
            else
              Column(
                children: [
                  for (final s in list) ...[
                    _hintCard(context, s),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            const SizedBox(height: 6),
            _principles(),
          ],
        );
      },
    );
  }

  Widget _filterChip(String key, String label) {
    return PillChip(
      label: label,
      active: _filter == key,
      onTap: () => setState(() => _filter = key),
    );
  }

  Widget _hintCard(BuildContext context, Suggestion s) {
    final (color, bg) = _severityColors(s.severity);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(_typeIcon(s.type), size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GColors.ink, height: 1.5),
                ),
                const SizedBox(height: 3),
                Text(
                  s.desc,
                  style: const TextStyle(fontSize: 12, color: GColors.muted, height: 1.6),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._actionButtons(context, s),
                    MiniBadge(
                      label: _severityLabel(s.severity),
                      color: color,
                      bg: bg,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actionButtons(BuildContext context, Suggestion s) {
    final store = AppStore.instance;
    final buttons = <Widget>[];

    Widget soft(String label, IconData icon, VoidCallback onTap, {bool danger = false}) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 13),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? GColors.danger : GColors.inkSoft,
          side: BorderSide(color: danger ? GColors.dangerWeak : GColors.lineStrong),
          backgroundColor: danger ? GColors.dangerWeak : GColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 32),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      );
    }

    if (s.itemId != null) {
      buttons.add(soft('查看', Icons.arrow_forward, () => openItemDetail(context, s.itemId!)));
      if (s.actions.contains('log_use')) {
        buttons.add(soft('记一次使用', Icons.check, () {
          store.logUsage(s.itemId!, type: 'use');
          toast(context, '已记录一次使用');
          setState(() {});
        }));
      }
      if (s.actions.contains('mark_idle')) {
        buttons.add(soft('标记闲置', Icons.schedule, () {
          store.patchItem(s.itemId!, (item) => item.status = 'idle');
          toast(context, '已标记为闲置');
          setState(() {});
        }));
      }
      if (s.actions.contains('mark_discarded')) {
        buttons.add(soft('处理掉', Icons.delete_outline, () async {
          final item = store.getItem(s.itemId!);
          if (item == null) return;
          final ok = await confirmDialog(
            context,
            title: '处理物品',
            message: '将「${item.name}」标记为已处理？它会从统计与建议中移除，记录仍会保留。',
            confirmText: '标记已处理',
            danger: true,
          );
          if (!ok || !context.mounted) return;
          store.patchItem(s.itemId!, (i) => i.status = 'discarded');
          toast(context, '已标记为已处理');
          setState(() {});
        }, danger: true));
      }
      if (s.actions.contains('return')) {
        buttons.add(soft('登记归还', Icons.refresh, () {
          store.logUsage(s.itemId!, type: 'return');
          toast(context, '已登记归还');
          setState(() {});
        }));
      }
    }
    if (s.spaceId != null) {
      buttons.add(soft('添加收纳单元', Icons.add, () {
        openSpaceForm(context, parentId: s.spaceId, type: 'container');
      }));
      buttons.add(soft('查看空间', Icons.arrow_forward, () => ShellNav.maybeOf(context)?.go(2)));
    }
    if (s.actions.contains('open_unplaced')) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => ShellNav.maybeOf(context)?.go(2),
          icon: const Icon(Icons.push_pin_outlined, size: 13),
          label: const Text('去归位'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }
    if (s.itemIds.isNotEmpty) {
      buttons.add(soft('查看同类物品', Icons.arrow_forward, () {
        if (s.name != null) {
          ShellNav.maybeOf(context)?.searchItems(s.name!);
        } else {
          ShellNav.maybeOf(context)?.go(1);
        }
      }));
    }
    return buttons;
  }

  Widget _principles() {
    const rules = [
      '为每件物品指定固定位置，用完立刻归位。',
      '每季度检查一次「90 天未使用」清单，果断处理低频物品。',
      '空间利用率保持在 80% 左右，留出余量才便于取放。',
    ];
    return SectionCard(
      title: '整理原则',
      sub: '三条让空间长期保持清爽的简单规则',
      child: Column(
        children: [
          for (var i = 0; i < rules.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiniBadge(label: '0${i + 1}'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rules[i],
                      style: const TextStyle(fontSize: 12.5, color: GColors.inkSoft, height: 1.7),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
