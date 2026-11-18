/// 物品库：搜索、筛选、网格/列表视图（对应 Web 版 items.js）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_detail.dart';
import 'item_form.dart';

const _sorts = {
  'recent': '最近添加',
  'value': '价值从高到低',
  'unused': '最久未使用',
  'name': '名称排序',
};

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => ItemsPageState();
}

class ItemsPageState extends State<ItemsPage> {
  String _q = '';
  String _category = 'all';
  String _status = 'all';
  String _sort = 'recent';
  bool _gridView = true;
  final _searchCtrl = TextEditingController();

  /// 供外壳调用（如「查看同类物品」直接带词搜索）
  void applySearch(String query) {
    setState(() {
      _q = query;
      _category = 'all';
      _status = 'all';
      _searchCtrl.text = query;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = store.activeItems();
        final totalValue = store.totalValue(active);
        final list = _currentList(store);

        return pageContainer(
          context,
          children: [
            PageHeader(
              title: '物品库',
              sub: '${active.length} 件在用物品 · 共 ${store.totalQuantity(active)} 件 · 资产价值 ${money(totalValue)}',
              actions: [
                FilledButton.icon(
                  onPressed: () => openItemForm(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增物品'),
                ),
              ],
            ),
            _toolbar(context),
            const SizedBox(height: 12),
            _categoryChips(store),
            const SizedBox(height: 10),
            Text(
              _q.isEmpty
                  ? '共 ${list.length} 件物品'
                  : '搜索「$_q」找到 ${list.length} 件物品',
              style: const TextStyle(fontSize: 12.5, color: GColors.muted),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              EmptyState(
                icon: _q.isEmpty ? Icons.inventory_2_outlined : Icons.search,
                title: _q.isEmpty ? '这里还没有物品' : '没有找到匹配的物品',
                desc: _q.isEmpty
                    ? '从新增第一件物品开始，为它指定一个固定的家。'
                    : '换个关键词，或清空筛选条件再试试。',
                action: FilledButton.icon(
                  onPressed: () => openItemForm(context),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('新增物品'),
                ),
              )
            else
              _list(context, store, list),
          ],
        );
      },
    );
  }

  Widget _toolbar(BuildContext context) {
    final wide = isWide(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: '搜索名称、标签、位置或备注',
                  prefixIcon: const Icon(Icons.search, size: 18, color: GColors.muted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 15, color: GColors.muted),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          },
                        ),
                ),
              ),
            ),
            if (wide) const SizedBox(width: 10),
            if (wide) _viewToggle(),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SelectField<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部状态')),
                  DropdownMenuItem(value: 'in_use', child: Text('在用')),
                  DropdownMenuItem(value: 'idle', child: Text('闲置')),
                  DropdownMenuItem(value: 'lent', child: Text('借出')),
                  DropdownMenuItem(value: 'discarded', child: Text('已处理')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'all'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectField<String>(
                value: _sort,
                items: [
                  for (final e in _sorts.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _sort = v ?? 'recent'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _viewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: GColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GColors.lineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(Icons.grid_view, _gridView, () => setState(() => _gridView = true)),
          _toggleBtn(Icons.format_list_bulleted, !_gridView, () => setState(() => _gridView = false)),
        ],
      ),
    );
  }

  Widget _toggleBtn(IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: active ? GColors.primaryWeak : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 15, color: active ? GColors.primary : GColors.muted),
      ),
    );
  }

  Widget _categoryChips(AppStore store) {
    final stats = store.categoryStats();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          PillChip(
            label: '全部 ${store.activeItems().length}',
            active: _category == 'all',
            onTap: () => setState(() => _category = 'all'),
          ),
          const SizedBox(width: 8),
          for (final row in stats.where((r) => r.count > 0)) ...[
            PillChip(
              label: '${row.category.name} ${row.count}',
              active: _category == row.category.id,
              dotColor: hexToColor(row.category.color),
              onTap: () => setState(() => _category = row.category.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  List<Item> _currentList(AppStore store) {
    var items = store.items.toList();
    if (_status == 'all') {
      items = items.where((it) => it.status != 'discarded').toList();
    } else {
      items = items.where((it) => it.status == _status).toList();
    }
    if (_category != 'all') {
      items = items.where((it) => it.categoryId == _category).toList();
    }
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((it) {
        final cat = store.getCategory(it.categoryId)?.name ?? '';
        final space = store.spacePathLabel(it.spaceId);
        final haystack =
            [it.name, cat, space, it.tags.join(' '), it.note].join(' ').toLowerCase();
        return haystack.contains(q);
      }).toList();
    }
    switch (_sort) {
      case 'value':
        items.sort((a, b) => b.value.compareTo(a.value));
      case 'unused':
        items.sort((a, b) => store.daysSinceLastUse(b).compareTo(store.daysSinceLastUse(a)));
      case 'name':
        items.sort((a, b) => a.name.compareTo(b.name));
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return items;
  }

  Widget _list(BuildContext context, AppStore store, List<Item> items) {
    if (!_gridView) {
      return Column(
        children: [
          for (final item in items) ...[
            _listRow(context, store, item),
            const SizedBox(height: 10),
          ],
        ],
      );
    }
    final wide = isWide(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items) SizedBox(width: width, child: _itemCard(context, store, item)),
          ],
        );
      },
    );
  }

  /* ------------------------- 网格卡片 ------------------------- */

  Widget _itemCard(BuildContext context, AppStore store, Item item) {
    final cat = store.getCategory(item.categoryId);
    final catColor = hexToColor(cat?.color);
    final unplaced = item.spaceId == null;
    return Material(
      color: GColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => openItemDetail(context, item.id),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardThumb(item, catColor, withOverlay: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: GColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.push_pin, size: 11, color: unplaced ? GColors.amber : GColors.muted2),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          unplaced ? '尚未归位' : store.spacePathLabel(item.spaceId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: unplaced ? GColors.amber : GColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        money(item.value),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GColors.ink),
                      ),
                      const Spacer(),
                      _cardAction(context, store, item, Icons.check, '记一次使用', () {
                        store.logUsage(item.id, type: 'use');
                        toast(context, '已记录使用「${item.name}」');
                      }),
                      const SizedBox(width: 2),
                      _cardAction(context, store, item, Icons.edit_outlined, '编辑', () {
                        openItemForm(context, item);
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardThumb(Item item, Color catColor, {required bool withOverlay}) {
    return Container(
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: AspectRatio(
        aspectRatio: 1.55,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: item.image != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ItemThumb(
                          image: item.image,
                          color: catColor,
                          size: double.infinity,
                          iconSize: 30,
                          fill: true,
                        ),
                      )
                    : Center(child: Icon(Icons.inventory_2_outlined, size: 30, color: catColor)),
              ),
            ),
            if (withOverlay)
              Positioned(
                top: 8,
                right: 8,
                child: StatusBadge(status: item.status),
              ),
            if (withOverlay && item.quantity > 1)
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '×${item.quantity}',
                    style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardAction(BuildContext context, AppStore store, Item item, IconData icon, String tip, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        color: GColors.muted,
        tooltip: tip,
        padding: EdgeInsets.zero,
        iconSize: 15,
      ),
    );
  }

  /* ------------------------- 列表行 ------------------------- */

  Widget _listRow(BuildContext context, AppStore store, Item item) {
    final cat = store.getCategory(item.categoryId);
    final catColor = hexToColor(cat?.color);
    return Material(
      color: GColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => openItemDetail(context, item.id),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              item.image != null
                  ? ItemThumb(image: item.image, color: catColor, size: 54, iconSize: 22, fill: true)
                  : ItemThumb(image: null, color: catColor, size: 54, iconSize: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: GColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cat?.name ?? '未分类'} · ${store.spacePathLabel(item.spaceId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: GColors.muted),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        StatusBadge(status: item.status),
                        if (item.quantity > 1) ...[
                          const SizedBox(width: 6),
                          TagChip(text: '×${item.quantity}'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(money(item.value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GColors.ink)),
              const SizedBox(width: 4),
              _cardAction(context, store, item, Icons.check, '记一次使用', () {
                store.logUsage(item.id, type: 'use');
                toast(context, '已记录使用「${item.name}」');
              }),
              _cardAction(context, store, item, Icons.edit_outlined, '编辑', () {
                openItemForm(context, item);
              }),
            ],
          ),
        ),
      ),
    );
  }
}
