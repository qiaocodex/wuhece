/// 总览（对应 Web 版 dashboard.js）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/dates.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_detail.dart';
import 'item_form.dart';
import 'space_form.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final stats = store.siteStats();
        final cats = store.categoryStats().where((c) => c.count > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final List<({Space room, SpaceUsage usage})> rooms =
            store.rootSpaces().map((r) => (room: r, usage: store.spaceUsage(r.id))).toList();
        final List<Item> recent = store.recentItems(5);
        final List<Suggestion> suggestions = store.getSuggestions().take(3).toList();
        final idleCount = store.activeItems().where((it) => it.status == 'idle').length;

        return pageContainer(
          context,
          children: [
            PageHeader(
              title: '${greeting()}，欢迎回来',
              sub: '${todayText()} · 共 ${stats.itemCount} 件物品，分布在 ${stats.roomCount} 个房间',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => openSpaceForm(context, type: 'room'),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('新增空间'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => openItemForm(context),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('新增物品'),
                ),
              ],
            ),
            StatGrid(children: [
              StatCard(
                icon: Icons.inventory_2_outlined,
                label: '物品总数',
                value: '${stats.itemCount}',
                valueSuffix: '条记录',
                badge: '${stats.quantity} 件',
                hint: stats.unplaced > 0 ? '${stats.unplaced} 件尚未归位' : '全部物品都有固定位置',
              ),
              StatCard(
                icon: Icons.account_balance_wallet_outlined,
                label: '资产总值',
                value: money(stats.value),
                hint: '按单价 × 数量估算',
                iconBg: GColors.accentWeak,
                iconColor: GColors.accent,
              ),
              StatCard(
                icon: Icons.archive_outlined,
                label: '空间平均利用率',
                value: '${stats.avgPct}',
                valueSuffix: '%',
                hint: '${stats.spaceCount} 个收纳节点 · 容量 ${stats.capacity}',
                iconBg: GColors.blueWeak,
                iconColor: GColors.blue,
              ),
              StatCard(
                icon: Icons.lightbulb_outlined,
                label: '待整理提醒',
                value: '${stats.suggestions}',
                hint: '$idleCount 件物品处于闲置状态',
                iconBg: GColors.amberWeak,
                iconColor: GColors.amber,
              ),
            ]),
            const SizedBox(height: kSectionGap),
            twoColumns(
              context,
              _spaceOverview(context, store, rooms),
              _categoryDonut(context, store, stats, cats),
            ),
            const SizedBox(height: kSectionGap),
            twoColumns(
              context,
              _recentItems(context, store, recent),
              _suggestionCard(context, suggestions),
            ),
          ],
        );
      },
    );
  }

  Widget _spaceOverview(
      BuildContext context, AppStore store, List<({Space room, SpaceUsage usage})> rooms) {
    return SectionCard(
      title: '空间概览',
      sub: '各房间的收纳压力',
      action: _cardLink(context, '管理空间', () => ShellNav.maybeOf(context)?.go(2)),
      child: rooms.isEmpty
          ? EmptyState(
              icon: Icons.space_dashboard_outlined,
              title: '还没有空间',
              desc: '创建房间和收纳单元，开始规划你的收纳体系。',
              action: FilledButton.icon(
                onPressed: () => openSpaceForm(context, type: 'room'),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('新增空间'),
              ),
            )
          : Column(
              children: [
                for (final row in rooms)
                  MeterBar(
                    name: row.room.name,
                    valueText:
                        '${row.usage.count} 件${row.usage.pct == null ? '' : ' · ${row.usage.pct}%'}',
                    pct: row.usage.pct,
                  ),
              ],
            ),
    );
  }

  Widget _categoryDonut(BuildContext context, AppStore store, SiteStats stats, List<CategoryStat> cats) {
    return SectionCard(
      title: '分类分布',
      sub: '按物品条目数量',
      action: _cardLink(context, '查看分析', () => ShellNav.maybeOf(context)?.go(4)),
      child: cats.isEmpty
          ? const EmptyState(title: '暂无分类数据', desc: '添加物品后会自动统计。', icon: Icons.donut_large)
          : Column(
              children: [
                Row(
                  children: [
                    DonutChart(
                      segments: [
                        for (final c in cats) DonutSegment(value: c.count.toDouble(), color: hexToColor(c.category.color)),
                      ],
                      centerTitle: '${stats.itemCount}',
                      centerSub: '件物品',
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: LegendList(
                        rows: [
                          for (final c in cats.take(5))
                            LegendRow(
                              color: hexToColor(c.category.color),
                              label: c.category.name,
                              value: '${c.count} 件',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _recentItems(BuildContext context, AppStore store, List<Item> recent) {
    return SectionCard(
      title: '最近添加',
      sub: '最新入库的物品',
      action: _cardLink(context, '全部物品', () => ShellNav.maybeOf(context)?.go(1)),
      child: recent.isEmpty
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              title: '还没有物品',
              action: FilledButton.icon(
                onPressed: () => openItemForm(context),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('新增物品'),
              ),
            )
          : Column(
              children: [
                for (final item in recent)
                  InkWell(
                    onTap: () => openItemDetail(context, item.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          ItemThumb(
                            image: item.image,
                            color: hexToColor(store.getCategory(item.categoryId)?.color),
                            size: 38,
                            iconSize: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GColors.ink),
                                ),
                                Text(
                                  store.spacePathLabel(item.spaceId),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: GColors.muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            money(item.value),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GColors.ink),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 14, color: GColors.muted2),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _suggestionCard(BuildContext context, List<Suggestion> suggestions) {
    return SectionCard(
      title: '整理提醒',
      sub: '优先处理这几件事',
      action: _cardLink(context, '全部建议', () => ShellNav.maybeOf(context)?.go(3)),
      child: suggestions.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: '一切井井有条',
              desc: '继续记录使用情况，系统会持续给出建议。',
            )
          : Column(
              children: [
                for (final s in suggestions)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _severityIcon(s.severity),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GColors.ink, height: 1.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                s.desc,
                                style: const TextStyle(fontSize: 11.5, color: GColors.muted, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _severityIcon(String severity) {
    final (bg, color) = switch (severity) {
      'high' => (GColors.dangerWeak, GColors.danger),
      'medium' => (GColors.amberWeak, GColors.amber),
      _ => (GColors.blueWeak, GColors.blue),
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.warning_amber_outlined, size: 14, color: color),
    );
  }

  Widget _cardLink(BuildContext context, String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: GColors.muted)),
          const Icon(Icons.chevron_right, size: 14, color: GColors.muted2),
        ],
      ),
    );
  }
}
