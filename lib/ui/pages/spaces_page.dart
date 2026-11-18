/// 收纳空间：房间卡片、层级收纳单元、待归位（对应 Web 版 spaces.js）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'space_form.dart';

class SpacesPage extends StatelessWidget {
  const SpacesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final rooms = store.rootSpaces();
        final usages = rooms.map((r) => store.spaceUsage(r.id)).where((u) => u.pct != null).toList();
        final avgPct = usages.isEmpty
            ? 0
            : (usages.fold(0, (s, u) => s + u.pct!) / usages.length).round();
        final unplaced = store.unplacedItems();
        final placedCount = store.activeItems().length - unplaced.length;
        final totalCapacity = store.spaces.fold(0, (s, sp) => s + sp.capacity);

        return pageContainer(
          context,
          children: [
            PageHeader(
              title: '收纳空间',
              sub: '${rooms.length} 个房间 · ${store.spaces.length} 个收纳节点 · 平均利用率 $avgPct%',
              actions: [
                FilledButton.icon(
                  onPressed: () => openSpaceForm(context, type: 'room'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增房间'),
                ),
              ],
            ),
            StatGrid(children: [
              StatCard(
                icon: Icons.meeting_room_outlined,
                label: '房间数量',
                value: '${rooms.length}',
              ),
              StatCard(
                icon: Icons.archive_outlined,
                label: '总容量（件）',
                value: '$totalCapacity',
                iconBg: GColors.blueWeak,
                iconColor: GColors.blue,
              ),
              StatCard(
                icon: Icons.inventory_2_outlined,
                label: '已归位物品',
                value: '$placedCount',
                valueSuffix: '件',
                iconBg: GColors.amberWeak,
                iconColor: GColors.amber,
              ),
              StatCard(
                icon: Icons.push_pin_outlined,
                label: '尚未归位',
                value: '${unplaced.length}',
                valueSuffix: '件',
                iconBg: GColors.accentWeak,
                iconColor: GColors.accent,
              ),
            ]),
            const SizedBox(height: kSectionGap),
            if (rooms.isEmpty)
              EmptyState(
                icon: Icons.space_dashboard_outlined,
                title: '还没有创建任何空间',
                desc: '先建立房间，再添加衣柜、抽屉等收纳单元，让物品有处可放。',
                action: FilledButton.icon(
                  onPressed: () => openSpaceForm(context, type: 'room'),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('创建第一个房间'),
                ),
              )
            else
              Column(
                children: [
                  for (final room in rooms) ...[
                    _RoomCard(room: room),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            if (unplaced.isNotEmpty) ...[
              const SizedBox(height: 8),
              _unplacedCard(context, unplaced),
            ],
            const SizedBox(height: 20),
            const Center(
              child: Text(
                '容量仅用于估算利用率，可随时调整；收纳单元可多层嵌套。',
                style: TextStyle(fontSize: 11.5, color: GColors.muted2),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _unplacedCard(BuildContext context, List<Item> unplaced) {
    final store = AppStore.instance;
    return SectionCard(
      title: '待归位物品',
      sub: '${unplaced.length} 件物品还没有指定收纳位置',
      action: const MiniBadge(label: '待整理', color: GColors.amber, bg: GColors.amberWeak),
      child: Column(
        children: [
          for (final item in unplaced)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  ItemThumb(
                    image: item.image,
                    color: hexToColor(store.getCategory(item.categoryId)?.color),
                    size: 36,
                    iconSize: 15,
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
                          '${money(item.price)} · ${item.tags.join(' / ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: GColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _assignSpace(context, item),
                    icon: const Icon(Icons.push_pin_outlined, size: 13),
                    label: const Text('指定位置'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: GColors.surfaceSoft,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _assignSpace(BuildContext context, Item item) async {
    final spaceId = await showResponsive<String>(
      context,
      builder: (ctx) => _AssignSpaceBody(item: item),
    );
    if (spaceId == null || !context.mounted) return;
    AppStore.instance.patchItem(item.id, (it) => it.spaceId = spaceId.isEmpty ? null : spaceId);
    toast(context, spaceId.isEmpty ? '已设为未归位' : '已归位');
  }
}

/* ------------------------- 房间卡片 ------------------------- */

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room});

  final Space room;

  IconData _typeIcon(String type) => switch (type) {
        'room' => Icons.meeting_room_outlined,
        'area' => Icons.layers_outlined,
        _ => Icons.inventory_2_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final usage = store.spaceUsage(room.id);
    final children = store.childSpaces(room.id);
    final sub =
        '${children.length} 个收纳节点 · 已放 ${usage.count} 件${usage.capacity > 0 ? ' / 容量 ${usage.capacity}' : ''}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: GColors.primaryWeak, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.meeting_room_outlined, size: 18, color: GColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GColors.ink),
                    ),
                    Text(sub, style: const TextStyle(fontSize: 12, color: GColors.muted)),
                  ],
                ),
              ),
              _roomTool(context, Icons.add, '添加区域', () {
                openSpaceForm(
                  context,
                  parentId: room.id,
                  type: room.type == 'room' ? 'area' : 'container',
                );
              }),
              _roomTool(context, Icons.edit_outlined, '编辑', () => openSpaceForm(context, editing: room)),
              _roomTool(context, Icons.delete_outline, '删除', () => _deleteSpace(context, store, room), danger: true),
            ],
          ),
          const SizedBox(height: 12),
          MeterBar(
            name: '空间利用率',
            valueText: usage.pct == null ? '未设置容量' : '${usage.pct}%',
            pct: usage.pct,
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Text(
                '还没有收纳单元',
                style: TextStyle(fontSize: 12, color: GColors.muted2),
              ),
            )
          else
            for (final child in children) _areaRow(context, store, child),
          TextButton.icon(
            onPressed: () {
              openSpaceForm(
                context,
                parentId: room.id,
                type: room.type == 'room' ? 'area' : 'container',
              );
            },
            icon: const Icon(Icons.add, size: 14),
            label: const Text('添加区域 / 收纳单元'),
            style: TextButton.styleFrom(
              foregroundColor: GColors.primary,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomTool(BuildContext context, IconData icon, String tip, VoidCallback onTap, {bool danger = false}) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        color: danger ? GColors.danger : GColors.muted,
        tooltip: tip,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _areaRow(BuildContext context, AppStore store, Space space, [int depth = 0]) {
    final usage = store.spaceUsage(space.id, includeChildren: false);
    final children = store.childSpaces(space.id);
    final pct = usage.pct;
    final barColor = pct != null && pct >= 100
        ? GColors.danger
        : pct != null && pct >= 90
            ? GColors.amber
            : GColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: EdgeInsets.only(left: depth * 18.0, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: GColors.surfaceSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GColors.line),
          ),
          child: Row(
            children: [
              Icon(
                _typeIcon(space.type),
                size: 15,
                color: space.type == 'container' ? GColors.accent : GColors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  space.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: GColors.ink),
                ),
              ),
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct == null ? 0 : (pct.clamp(0, 100)) / 100,
                    minHeight: 5,
                    backgroundColor: GColors.bgDeep,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${usage.count}件${pct == null ? '' : ' · $pct%'}',
                style: const TextStyle(fontSize: 11, color: GColors.muted),
              ),
              const SizedBox(width: 4),
              if (space.type != 'container')
                _areaTool(context, Icons.add, () {
                  openSpaceForm(context, parentId: space.id, type: 'container');
                }),
              _areaTool(context, Icons.edit_outlined, () => openSpaceForm(context, editing: space)),
              _areaTool(context, Icons.delete_outline, () => _deleteSpace(context, store, space), danger: true),
            ],
          ),
        ),
        if (children.isNotEmpty)
          for (final child in children) _areaRow(context, store, child, depth + 1),
      ],
    );
  }

  Widget _areaTool(BuildContext context, IconData icon, VoidCallback onTap, {bool danger = false}) {
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 13),
        color: danger ? GColors.danger : GColors.muted,
        padding: EdgeInsets.zero,
        iconSize: 13,
      ),
    );
  }

  /// 删除空间（含子级）；其下物品会变为未归位
  Future<void> _deleteSpace(BuildContext context, AppStore store, Space space) async {
    final descendants = store.collectDescendantIds(space.id);
    final itemCount = store.items.where((it) => descendants.contains(it.spaceId)).length;
    final extra = <String>[];
    if (descendants.length > 1) extra.add('其下 ${descendants.length - 1} 个收纳单元会一并删除，');
    if (itemCount > 0) extra.add('$itemCount 件物品会变为未归位状态。');
    final ok = await confirmDialog(
      context,
      title: '删除空间',
      message: '确定删除「${space.name}」吗？${extra.join()}',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    store.deleteSpace(space.id);
    toast(context, '空间已删除');
  }
}

/* ------------------------- 指定位置弹层 ------------------------- */

class _AssignSpaceBody extends StatefulWidget {
  const _AssignSpaceBody({required this.item});

  final Item item;

  @override
  State<_AssignSpaceBody> createState() => _AssignSpaceBodyState();
}

class _AssignSpaceBodyState extends State<_AssignSpaceBody> {
  late String _spaceId;

  @override
  void initState() {
    super.initState();
    _spaceId = widget.item.spaceId ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final rows = store.flattenSpaces();
    return FormScaffold(
      title: '为「${widget.item.name}」指定位置',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _spaceId),
          child: const Text('保存位置'),
        ),
      ],
      body: FormField2(
        label: '收纳位置',
        child: SelectField<String>(
          value: _spaceId,
          items: [
            const DropdownMenuItem(value: '', child: Text('未归位')),
            for (final row in rows)
              DropdownMenuItem(
                value: row.space.id,
                child: Text(
                  '${'　' * row.depth}${row.depth > 0 ? '└ ' : ''}${row.space.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _spaceId = v ?? ''),
        ),
      ),
    );
  }
}
