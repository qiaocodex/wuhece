/// 物品库：搜索、筛选、网格/列表视图（对应 Web 版 items.js）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'image_viewer_page.dart';
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
  String _view = 'grid'; // grid | list | photos
  bool _searchFocused = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  /// 供外壳调用（如「查看同类物品」直接带词搜索）
  void applySearch(String query) {
    setState(() {
      _q = query;
      _category = 'all';
      _status = 'all';
      _searchCtrl.text = query;
    });
    AppStore.instance.addSearchHistory(query);
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
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
              style: TextStyle(fontSize: 12.5, color: context.gc.muted),
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
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (v) {
                  AppStore.instance.addSearchHistory(v);
                  _searchFocus.unfocus();
                },
                decoration: InputDecoration(
                  hintText: '搜索名称、标签、位置或备注',
                  prefixIcon: Icon(Icons.search, size: 18, color: context.gc.muted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, size: 15, color: context.gc.muted),
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
        if (_searchFocused && _q.isEmpty) _searchHistory(),
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

  /// 搜索历史（仅聚焦且输入为空时显示）
  Widget _searchHistory() {
    final history = AppStore.instance.searchHistory();
    if (history.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.gc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.gc.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最近搜索', style: TextStyle(fontSize: 11.5, color: context.gc.muted2)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  AppStore.instance.clearSearchHistory();
                  setState(() {});
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('清空', style: TextStyle(fontSize: 11.5, color: context.gc.muted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in history)
                PillChip(
                  label: q,
                  active: false,
                  onTap: () {
                    _searchCtrl.text = q;
                    setState(() {
                      _q = q;
                      _category = 'all';
                      _status = 'all';
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: context.gc.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.gc.lineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(Icons.grid_view, _view == 'grid', () => setState(() => _view = 'grid')),
          _toggleBtn(Icons.format_list_bulleted, _view == 'list', () => setState(() => _view = 'list')),
          _toggleBtn(Icons.photo_library_outlined, _view == 'photos', () => setState(() => _view = 'photos')),
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
          color: active ? context.gc.primaryWeak : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 15, color: active ? context.gc.primary : context.gc.muted),
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

  /// 图片墙：只展示有照片的物品
  Widget _photosView(BuildContext context, AppStore store, List<Item> items) {
    final photoItems = items.where((it) => (it.image ?? '').isNotEmpty).toList();
    if (photoItems.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: '还没有带图片的物品',
        desc: '给物品拍张照，就能在这里快速浏览。',
        action: FilledButton.icon(
          onPressed: () => openItemForm(context),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('新增物品'),
        ),
      );
    }
    final wide = isWide(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 4 : 3;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < photoItems.length; i++)
              SizedBox(width: width, child: _photoCell(context, store, photoItems, i)),
          ],
        );
      },
    );
  }

  Widget _photoCell(BuildContext context, AppStore store, List<Item> photoItems, int index) {
    final item = photoItems[index];
    return Material(
      color: GColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => openImageViewer(context, photoItems, index),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: AspectRatio(
                aspectRatio: 1,
                child: ItemThumb(image: item.image, color: GColors.primary, size: double.infinity, iconSize: 32, fill: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.gc.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    store.spacePathLabel(item.spaceId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.gc.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, AppStore store, List<Item> items) {
    if (_view == 'photos') {
      return _photosView(context, store, items);
    }
    if (_view == 'list') {
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
      color: context.gc.surface,
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
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.gc.ink),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.push_pin, size: 11, color: unplaced ? context.gc.amber : context.gc.muted2),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          unplaced ? '尚未归位' : store.spacePathLabel(item.spaceId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: unplaced ? context.gc.amber : context.gc.muted,
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
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.gc.ink),
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
        color: context.gc.muted,
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
      color: context.gc.surface,
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
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.gc.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cat?.name ?? '未分类'} · ${store.spacePathLabel(item.spaceId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: context.gc.muted),
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
              Text(money(item.value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.gc.ink)),
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
