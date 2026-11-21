/// 数据分析（对应 Web 版 analytics.js）
library;

import 'dart:math' show max;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/dates.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_detail.dart';
import '../widgets/line_chart.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final stats = store.siteStats();
        final cats = store.categoryStats().where((c) => c.count > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final statuses = store.statusStats().where((s) => s.count > 0 && s.key != 'discarded').toList();
        final List<({Space room, SpaceUsage usage})> rooms =
            store.rootSpaces().map((r) => (room: r, usage: store.spaceUsage(r.id))).toList()
              ..sort((a, b) => (b.usage.pct ?? 0).compareTo(a.usage.pct ?? 0));
        final years = store.purchaseYearStats();
        final ranking = store.usageRanking(6);
        final active = store.activeItems();
        final inUseCount = active.where((it) => it.status == 'in_use').length;
        final idleValue = active.where((it) => it.status == 'idle').fold(0.0, (s, it) => s + it.value);
        final avgValue = active.isEmpty ? 0.0 : stats.value / active.length;
        final inUsePct = active.isEmpty ? 0 : (inUseCount / active.length * 100).round();
        final maxCatValue = cats.isEmpty ? 1.0 : cats.map((c) => c.value).reduce(max);
        final maxYearCount = years.isEmpty ? 1 : years.map((y) => y.count).reduce(max);
        final disposal = store.disposalStats();
        final series = store.monthlyAssetSeries();
        final recentDisposed = store.disposedItems().toList()
          ..sort((a, b) => (b.disposedAt ?? '').compareTo(a.disposedAt ?? ''));

        return pageContainer(
          context,
          children: [
            const PageHeader(title: '数据分析', sub: '看清资产结构、空间压力与使用习惯'),
            StatGrid(children: [
              StatCard(
                icon: Icons.account_balance_wallet_outlined,
                label: '在用资产总值',
                value: money(stats.value),
                hint: '共 ${stats.quantity} 件物品',
              ),
              StatCard(
                icon: Icons.sell_outlined,
                label: '平均单件价值',
                value: money(avgValue),
                hint: '按物品条目数计算',
                iconBg: context.gc.blueWeak,
                iconColor: context.gc.blue,
              ),
              StatCard(
                icon: Icons.check_circle_outline,
                label: '在用比例',
                value: '$inUsePct',
                valueSuffix: '%',
                hint: '$inUseCount 件处于在用状态',
                iconBg: context.gc.primaryWeak,
                iconColor: context.gc.primary,
              ),
              StatCard(
                icon: Icons.schedule,
                label: '闲置资产价值',
                value: money(idleValue),
                hint: '可考虑转售或转赠',
                iconBg: context.gc.amberWeak,
                iconColor: context.gc.amber,
              ),
            ]),
            const SizedBox(height: kSectionGap),
            twoColumns(
              context,
              _categoryValueCard(cats, maxCatValue),
              _categoryDonutCard(cats, active.length),
            ),
            const SizedBox(height: kSectionGap),
            twoColumns(
              context,
              _roomUsageCard(context, rooms),
              _statusCard(context, statuses, active.length),
            ),
            const SizedBox(height: kSectionGap),
            twoColumns(
              context,
              _yearCard(context, years, maxYearCount),
              _rankingCard(context, ranking),
            ),
            const SizedBox(height: kSectionGap),
            StatGrid(children: [
              StatCard(
                icon: Icons.delete_sweep_outlined,
                label: '已处置物品',
                value: '${disposal.count}',
                valueSuffix: '件',
                hint: '原值合计 ${money(disposal.originalValue)}',
                iconBg: context.gc.bgDeep,
                iconColor: context.gc.inkSoft,
              ),
              StatCard(
                icon: Icons.savings_outlined,
                label: '处置残值',
                value: money(disposal.salvage),
                hint: '卖出 / 回收所得',
                iconBg: context.gc.primaryWeak,
                iconColor: context.gc.primary,
              ),
              StatCard(
                icon: Icons.trending_down,
                label: '残值回收率',
                value: '${disposal.recoveryPct}',
                valueSuffix: '%',
                hint: '残值 ÷ 对应原值',
                iconBg: context.gc.accentWeak,
                iconColor: context.gc.accent,
              ),
            ]),
            const SizedBox(height: kSectionGap),
            twoColumns(
              context,
              _disposalCard(context, recentDisposed),
              _trendCard(series),
            ),
          ],
        );
      },
    );
  }

  Widget _categoryValueCard(List<CategoryStat> cats, double maxCatValue) {
    return SectionCard(
      title: '分类资产价值',
      sub: '按当前在用物品计算',
      child: cats.isEmpty
          ? const EmptyState(title: '暂无数据', desc: '添加物品后即可看到分类价值分布。', icon: Icons.sell_outlined)
          : Column(
              children: [
                for (final c in cats.take(8))
                  MeterBar(
                    name: c.category.name,
                    valueText: '${money(c.value)} · ${c.count} 件',
                    pct: (c.value / maxCatValue * 100).round(),
                    color: hexToColor(c.category.color),
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: hexToColor(c.category.color),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _categoryDonutCard(List<CategoryStat> cats, int activeCount) {
    return SectionCard(
      title: '分类数量分布',
      sub: '各分类物品条目占比',
      child: cats.isEmpty
          ? const EmptyState(title: '暂无数据', icon: Icons.donut_large)
          : Row(
              children: [
                DonutChart(
                  segments: [
                    for (final c in cats) DonutSegment(value: c.count.toDouble(), color: hexToColor(c.category.color)),
                  ],
                  centerTitle: '$activeCount',
                  centerSub: '件物品',
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: LegendList(
                    rows: [
                      for (final c in cats.take(6))
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
    );
  }

  Widget _roomUsageCard(BuildContext context, List<({Space room, SpaceUsage usage})> rooms) {
    return SectionCard(
      title: '房间利用率',
      sub: '库存容量压力排行',
      action: TextButton(
        onPressed: () => ShellNav.maybeOf(context)?.go(2),
        style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('管理空间', style: TextStyle(fontSize: 12.5, color: context.gc.muted)),
          Icon(Icons.chevron_right, size: 14, color: context.gc.muted2),
        ]),
      ),
      child: rooms.isEmpty
          ? const EmptyState(
              title: '还没有空间',
              desc: '创建房间与收纳单元后，可以查看容量使用情况。',
              icon: Icons.space_dashboard_outlined,
            )
          : Column(
              children: [
                for (final row in rooms)
                  MeterBar(
                    name: row.room.name,
                    valueText: '${row.usage.count} 件${row.usage.capacity > 0 ? ' / ${row.usage.capacity}' : ''}'
                        '${row.usage.pct == null ? '' : ' · ${row.usage.pct}%'}',
                    pct: row.usage.pct,
                  ),
              ],
            ),
    );
  }

  Widget _statusCard(BuildContext context, List<StatusCount> statuses, int activeCount) {
    return SectionCard(
      title: '物品状态',
      sub: '在用 / 闲置 / 借出分布',
      child: statuses.isEmpty
          ? const EmptyState(title: '暂无数据', icon: Icons.sell_outlined)
          : Column(
              children: [
                for (final s in statuses)
                  MeterBar(
                    name: s.label,
                    valueText: '${s.count} 件 · ${activeCount == 0 ? 0 : (s.count / activeCount * 100).round()}%',
                    pct: activeCount == 0 ? 0 : (s.count / activeCount * 100).round(),
                    color: switch (s.key) {
                      'in_use' => context.gc.primary,
                      'idle' => context.gc.amber,
                      'lent' => context.gc.blue,
                      _ => context.gc.muted2,
                    },
                  ),
              ],
            ),
    );
  }

  Widget _yearCard(BuildContext context, List<YearStat> years, int maxYearCount) {
    return SectionCard(
      title: '购入年份分布',
      sub: '了解物品的新旧结构与沉没成本',
      child: years.isEmpty
          ? const EmptyState(title: '暂无购入时间数据', icon: Icons.schedule)
          : Column(
              children: [
                for (final y in years)
                  MeterBar(
                    name: '${y.year} 年',
                    valueText: '${y.count} 件 · ${money(y.value)}',
                    pct: (y.count / maxYearCount * 100).round(),
                    color: context.gc.accent,
                  ),
              ],
            ),
    );
  }

  Widget _rankingCard(BuildContext context, List<UsageRankRow> ranking) {
    return SectionCard(
      title: '高频使用物品',
      sub: '按使用记录次数统计',
      child: ranking.isEmpty
          ? const EmptyState(
              title: '还没有使用记录',
              desc: '在物品详情里记录使用，可以更好判断使用频率。',
              icon: Icons.bar_chart,
            )
          : Column(
              children: [
                for (var i = 0; i < ranking.length; i++)
                  InkWell(
                    onTap: () => openItemDetail(context, ranking[i].item.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: i < 3 ? context.gc.primaryWeak : context.gc.bgDeep,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: i < 3 ? context.gc.primary : context.gc.muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ranking[i].item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12.5, color: context.gc.inkSoft),
                                      ),
                                    ),
                                    Text(
                                      '${ranking[i].uses} 次',
                                      style: TextStyle(fontSize: 11.5, color: context.gc.muted),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: ranking[0].uses == 0
                                        ? 0
                                        : ranking[i].uses / ranking[0].uses,
                                    minHeight: 6,
                                    backgroundColor: context.gc.bgDeep,
                                    valueColor: AlwaysStoppedAnimation(context.gc.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _disposalCard(BuildContext context, List<Item> recentDisposed) {
    return SectionCard(
      title: '处置记录',
      sub: '最近处置的物品与残值',
      child: recentDisposed.isEmpty
          ? const EmptyState(
              title: '还没有处置记录',
              desc: '在整理建议或物品详情里「处理掉」物品后，这里会记录残值与回收率。',
              icon: Icons.delete_sweep_outlined,
            )
          : Column(
              children: [
                for (final item in recentDisposed.take(6))
                  InkWell(
                    onTap: () => openItemDetail(context, item.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: context.gc.ink,
                                  ),
                                ),
                                Text(
                                  '处置于 ${item.disposedAt != null ? formatDate(item.disposedAt) : '—'}'
                                  ' · 原值 ${money(item.value)}',
                                  style: TextStyle(fontSize: 11.5, color: context.gc.muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.disposalPrice != null ? money(item.disposalPrice!) : '—',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: item.disposalPrice != null ? context.gc.primary : context.gc.muted2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _trendCard(List<AssetMonthPoint> series) {
    return SectionCard(
      title: '月度资产变化',
      sub: '按月累计购入 − 处置回收',
      child: series.isEmpty
          ? const EmptyState(
              title: '暂无资产数据',
              desc: '录入物品后即可看到资产变化曲线。',
              icon: Icons.show_chart,
            )
          : AssetTrendChart(points: series),
    );
  }
}
