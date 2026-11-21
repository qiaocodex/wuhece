/// 数据层：本地持久化 + 业务查询（对应 Web 版 store.js）
///
/// 一次全局单例 [AppStore.instance]，UI 通过 ChangeNotifier 监听刷新。
/// 持久化键沿用 Web 版 `guiwu.data.v2`，JSON 结构完全一致，备份互通。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/dates.dart';
import '../services/id.dart';
import 'seed_data.dart';

/// 整理建议条目（由规则引擎自动生成）
class Suggestion {
  const Suggestion({
    required this.key,
    required this.type,
    required this.severity,
    required this.title,
    required this.desc,
    required this.actions,
    this.itemId,
    this.spaceId,
    this.name,
    this.itemIds = const [],
  });

  final String key;
  final String type; // idle / warranty / duplicate / space / lent / unplaced
  final String severity; // high / medium / low
  final String title;
  final String desc;
  final String? itemId;
  final String? spaceId;
  final String? name;
  final List<String> itemIds;
  final List<String> actions;
}

class AppStore extends ChangeNotifier {
  AppStore(this._prefs) {
    _instance = this;
  }

  /// 全局单例（便于无 context 的服务层访问，如 CSV 导入）
  static AppStore? _instance;
  static AppStore get instance => _instance!;

  final SharedPreferences _prefs;

  static const storageKey = 'guiwu.data.v2';
  static const welcomeKey = 'guiwu.seen-welcome';

  List<Item> items = [];
  List<Category> categories = [];
  List<Space> spaces = [];
  AppSettings settings = AppSettings();

  /// 最近一次持久化失败的提示（UI 上以轻提示呈现）
  String? saveError;

  /// 从本地存储载入；无有效数据时载入示例数据
  void load() {
    final raw = _prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final loadedItems =
            (parsed['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Item.fromJson).toList();
        final loadedCats =
            (parsed['categories'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Category.fromJson).toList();
        final loadedSpaces =
            (parsed['spaces'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Space.fromJson).toList();
        if (loadedItems.isNotEmpty || loadedCats.isNotEmpty || loadedSpaces.isNotEmpty) {
          items = loadedItems;
          categories = loadedCats;
          spaces = loadedSpaces;
          settings = AppSettings.fromJson(parsed['settings'] as Map<String, dynamic>?);
          return;
        }
      } catch (err) {
        debugPrint('数据解析失败，使用示例数据：$err');
      }
    }
    _replace(seedData());
    _save();
    notifyListeners();
  }

  void _replace(Map<String, dynamic> data) {
    items = data['items'] as List<Item>;
    categories = data['categories'] as List<Category>;
    spaces = data['spaces'] as List<Space>;
    settings = data['settings'] as AppSettings? ?? AppSettings();
    saveError = null;
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'spaces': spaces.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
      };

  /// 导出完整备份（与 Web 版字段一致）
  ///
  /// 注意：'app': 'guiwu' 与存储键 [storageKey] 是数据互通的兼容标识，
  /// 应用更名为「物盒册」后仍保持不变，请勿随显示名修改。
  String exportJson() {
    final encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'app': 'guiwu',
      'version': 1,
      'exportedAt': nowIso(),
      ...toJson(),
    });
  }

  /// 导入备份（覆盖当前全部数据），格式错误时抛异常
  void importJson(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    final importedItems =
        (data['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Item.fromJson).toList();
    final importedCats =
        (data['categories'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Category.fromJson).toList();
    final importedSpaces =
        (data['spaces'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Space.fromJson).toList();
    if (data['items'] is! List || data['categories'] is! List || data['spaces'] is! List) {
      throw const FormatException('文件格式不正确');
    }
    items = importedItems;
    categories = importedCats;
    spaces = importedSpaces;
    settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>?);
    _commit();
  }

  /// 重置为示例数据
  void resetToSeed() {
    _replace(seedData());
    _commit();
  }

  /// 清空全部数据
  void clearAll() {
    _replace(emptyData());
    _commit();
  }

  /// 粗略估算本地数据大小（设置页展示用）
  int storageBytes() => utf8.encode(jsonEncode(toJson())).length;

  bool get seenWelcome => _prefs.getBool(welcomeKey) ?? false;

  Future<void> markWelcomeSeen() => _prefs.setBool(welcomeKey, true);

  void _commit() {
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      await _prefs.setString(storageKey, jsonEncode(toJson()));
      saveError = null;
    } catch (err) {
      saveError = '本地存储写入失败，数据或图片可能未保存';
    }
  }

  /* ------------------------- 物品 ------------------------- */

  Item? getItem(String id) {
    for (final it in items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// 新建物品（入库到列表头部）
  Item addItem({
    required String name,
    required String categoryId,
    String? spaceId,
    List<String>? tags,
    int quantity = 1,
    double price = 0,
    String? purchaseDate,
    int warrantyMonths = 0,
    String status = 'in_use',
    String? image,
    String note = '',
  }) {
    final now = nowIso();
    final item = Item(
      id: uid('it'),
      name: name.trim(),
      categoryId: categoryId.isEmpty ? (categories.isNotEmpty ? categories.first.id : 'cat-other') : categoryId,
      spaceId: spaceId,
      tags: tags ?? const [],
      quantity: quantity < 1 ? 1 : quantity,
      price: price < 0 ? 0 : price,
      purchaseDate: purchaseDate,
      warrantyMonths: warrantyMonths < 0 ? 0 : warrantyMonths,
      status: status,
      image: image,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
    );
    items.insert(0, item);
    _commit();
    return item;
  }

  /// 批量新增（CSV 导入），返回导入数量
  int addItemsBulk(List<Item> newItems) {
    final valid = newItems.where((it) => it.name.trim().isNotEmpty).toList();
    if (valid.isEmpty) return 0;
    items = [...valid, ...items];
    _commit();
    return valid.length;
  }

  /// 编辑物品（草稿字段写回 + 更新时间戳）
  void updateItem(String id, Item edited) {
    final idx = items.indexWhere((it) => it.id == id);
    if (idx < 0) return;
    final target = items[idx];
    edited.applyTo(target);
    target.updatedAt = nowIso();
    _commit();
  }

  /// 直接修改物品（轻量 patch，例如标记闲置）
  void patchItem(String id, void Function(Item item) patch) {
    final item = getItem(id);
    if (item == null) return;
    patch(item);
    item.updatedAt = nowIso();
    _commit();
  }

  void deleteItem(String id) {
    items.removeWhere((it) => it.id == id);
    _commit();
  }

  /// 记录使用 / 借出 / 归还
  void logUsage(String id, {String type = 'use', String note = ''}) {
    final item = getItem(id);
    if (item == null) return;
    item.logs.insert(0, UsageLog(id: uid('log'), type: type, at: nowIso(), note: note));
    if (type == 'lend') item.status = 'lent';
    if (type == 'return') item.status = 'in_use';
    item.updatedAt = nowIso();
    _commit();
  }

  /* ------------------------- 空间 ------------------------- */

  Space? getSpace(String id) {
    for (final s in spaces) {
      if (s.id == id) return s;
    }
    return null;
  }

  Space addSpace({required String name, String type = 'area', String? parentId, int capacity = 0}) {
    final space = Space(
      id: uid('sp'),
      name: name.trim().isEmpty ? '未命名空间' : name.trim(),
      type: type,
      parentId: parentId,
      capacity: capacity < 0 ? 0 : capacity,
    );
    spaces.add(space);
    _commit();
    return space;
  }

  void updateSpace(String id, Space edited) {
    final idx = spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final space = spaces[idx];
    space.name = edited.name;
    space.type = edited.type;
    space.parentId = edited.parentId;
    space.capacity = edited.capacity;
    _commit();
  }

  /// 删除空间（含子级），其下物品变为未归位
  void deleteSpace(String id) {
    final ids = collectDescendantIds(id);
    spaces.removeWhere((s) => ids.contains(s.id));
    for (final it in items) {
      if (ids.contains(it.spaceId)) it.spaceId = null;
    }
    _commit();
  }

  List<String> collectDescendantIds(String id) {
    final result = [id];
    void walk(String parentId) {
      for (final s in spaces) {
        if (s.parentId == parentId) {
          result.add(s.id);
          walk(s.id);
        }
      }
    }
    walk(id);
    return result;
  }

  List<Space> childSpaces(String? parentId) => spaces.where((s) => s.parentId == parentId).toList();

  List<Space> rootSpaces() => spaces.where((s) => s.parentId == null || s.parentId!.isEmpty).toList();

  /// 深度优先平铺（带层级深度）
  List<SpaceDepth> flattenSpaces() {
    final rows = <SpaceDepth>[];
    void walk(String? parentId, int depth) {
      for (final s in childSpaces(parentId)) {
        rows.add(SpaceDepth(space: s, depth: depth));
        walk(s.id, depth + 1);
      }
    }
    walk(null, 0);
    return rows;
  }

  List<Space> spacePath(String id) {
    final path = <Space>[];
    var current = getSpace(id);
    var guard = 0;
    while (current != null && guard < 12) {
      path.insert(0, current);
      current = current.parentId == null ? null : getSpace(current.parentId!);
      guard += 1;
    }
    return path;
  }

  String spacePathLabel(String? id, [String divider = ' / ']) {
    if (id == null) return '未归位';
    final path = spacePath(id);
    return path.isEmpty ? '未归位' : path.map((s) => s.name).join(divider);
  }

  /* ------------------------- 分类 ------------------------- */

  Category? getCategory(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Category addCategory(String name, String color) {
    final cat = Category(id: uid('cat'), name: name.trim(), color: color);
    categories.add(cat);
    _commit();
    return cat;
  }

  void updateCategory(String id, {String? name, String? color}) {
    final cat = getCategory(id);
    if (cat == null) return;
    if (name != null) cat.name = name;
    if (color != null) cat.color = color;
    _commit();
  }

  /// 按名称查找分类，不存在则创建（CSV 导入用）
  String? ensureCategory(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return categories.isNotEmpty ? categories.first.id : null;
    for (final c in categories) {
      if (c.name == clean) return c.id;
    }
    final cat = Category(id: uid('cat'), name: clean, color: '#9a9a9a');
    categories.add(cat);
    return cat.id;
  }

  bool deleteCategory(String id) {
    if (categories.length <= 1) return false;
    final fallback = categories.firstWhere((c) => c.id != id);
    categories.removeWhere((c) => c.id == id);
    for (final it in items) {
      if (it.categoryId == id) it.categoryId = fallback.id;
    }
    _commit();
    return true;
  }

  /* ------------------------- 偏好 ------------------------- */

  void updateSettings({int? idleDays, String? currency, String? owner}) {
    if (idleDays != null) settings.idleDays = idleDays;
    if (currency != null) settings.currency = currency;
    if (owner != null) settings.owner = owner;
    _commit();
  }

  /* ------------------------- 统计 ------------------------- */

  List<Item> activeItems() => items.where((it) => it.status != 'discarded').toList();

  double totalValue([List<Item>? source]) {
    return (source ?? activeItems()).fold(0.0, (sum, it) => sum + it.value);
  }

  int totalQuantity([List<Item>? source]) {
    return (source ?? activeItems()).fold(0, (sum, it) => sum + it.quantity);
  }

  List<CategoryStat> categoryStats() {
    final map = <String, CategoryStatBuilder>{};
    for (final c in categories) {
      map[c.id] = CategoryStatBuilder(c);
    }
    for (final it in activeItems()) {
      map.putIfAbsent(
        it.categoryId,
        () => CategoryStatBuilder(Category(id: it.categoryId, name: '未分类', color: '#8b8377')),
      );
      map[it.categoryId]!.count += 1;
      map[it.categoryId]!.qty += it.quantity;
      map[it.categoryId]!.value += it.value;
    }
    return map.values
        .map((b) => CategoryStat(category: b.category, count: b.count, qty: b.qty, value: b.value))
        .toList();
  }

  List<StatusCount> statusStats() {
    return kStatusMeta.keys.map((key) {
      return StatusCount(
        key: key,
        label: kStatusMeta[key]!.label,
        tone: kStatusMeta[key]!.tone,
        count: items.where((it) => it.status == key).length,
      );
    }).toList();
  }

  int spaceItemCount(String spaceId, {bool includeChildren = true}) {
    final ids = includeChildren ? collectDescendantIds(spaceId) : [spaceId];
    return items.where((it) => ids.contains(it.spaceId) && it.status != 'discarded').length;
  }

  SpaceUsage spaceUsage(String spaceId, {bool includeChildren = true}) {
    final space = getSpace(spaceId);
    final count = spaceItemCount(spaceId, includeChildren: includeChildren);
    final capacity = space?.capacity ?? 0;
    int? pct;
    if (capacity > 0) {
      pct = (count / capacity * 100).round();
      pct = pct > 999 ? 999 : pct;
    }
    return SpaceUsage(space: space, count: count, capacity: capacity, pct: pct);
  }

  List<Item> unplacedItems() {
    return activeItems().where((it) => it.spaceId == null || getSpace(it.spaceId!) == null).toList();
  }

  String? lastUsedAt(Item item) {
    String? best;
    for (final l in item.logs) {
      if (best == null || l.at.compareTo(best) > 0) best = l.at;
    }
    return best ?? item.purchaseDate ?? item.createdAt;
  }

  int daysSinceLastUse(Item item) => daysSince(lastUsedAt(item)) ?? 0;

  String? warrantyEnd(Item item) {
    if (item.purchaseDate == null || item.purchaseDate!.isEmpty || item.warrantyMonths <= 0) return null;
    return addMonths(item.purchaseDate, item.warrantyMonths);
  }

  List<Item> recentItems([int limit = 5]) {
    final list = activeItems().toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  /// 高频使用排行（按 use 记录数）
  List<UsageRankRow> usageRanking([int limit = 6]) {
    final rows = <UsageRankRow>[];
    for (final it in activeItems()) {
      final uses = it.logs.where((l) => l.type == 'use').length;
      if (uses > 0) rows.add(UsageRankRow(item: it, uses: uses));
    }
    rows.sort((a, b) => b.uses.compareTo(a.uses));
    return rows.take(limit).toList();
  }

  List<YearStat> purchaseYearStats() {
    final map = <String, YearStat>{};
    for (final it in activeItems()) {
      if (it.purchaseDate == null || it.purchaseDate!.length < 4) continue;
      final year = it.purchaseDate!.substring(0, 4);
      final row = map.putIfAbsent(year, () => YearStat(year: year));
      row.count += 1;
      row.value += it.value;
    }
    final list = map.values.toList()..sort((a, b) => a.year.compareTo(b.year));
    return list;
  }

  /* ------------------------- 整理建议引擎 ------------------------- */

  List<Suggestion> getSuggestions() {
    final idleLimit = settings.idleDays;
    final out = <Suggestion>[];

    for (final it in activeItems()) {
      final days = daysSinceLastUse(it);

      if (it.status == 'lent') {
        String? lastLend;
        for (final l in it.logs) {
          if (l.type == 'lend' && (lastLend == null || l.at.compareTo(lastLend) > 0)) lastLend = l.at;
        }
        final lendDays = lastLend != null ? (daysSince(lastLend) ?? 0) : days;
        if (lendDays >= 30) {
          out.add(Suggestion(
            key: 'lent-${it.id}',
            type: 'lent',
            severity: 'high',
            itemId: it.id,
            title: '「${it.name}」借出 $lendDays 天仍未归还',
            desc: '长期外借容易遗忘，建议联系对方确认归还时间，或登记为已归还。',
            actions: const ['return', 'view'],
          ));
        }
        continue;
      }

      if (it.status != 'idle' && days >= idleLimit) {
        out.add(Suggestion(
          key: 'idle-${it.id}',
          type: 'idle',
          severity: days >= idleLimit * 2 ? 'high' : 'medium',
          itemId: it.id,
          title: '「${it.name}」已 $days 天未使用',
          desc: '可以移到更低频的收纳区，或标记为闲置准备转赠、出售，为常用物品腾出位置。',
          actions: const ['mark_idle', 'log_use', 'view'],
        ));
      } else if (it.status == 'idle' && days >= 60) {
        out.add(Suggestion(
          key: 'idle2-${it.id}',
          type: 'idle',
          severity: 'medium',
          itemId: it.id,
          title: '闲置物品「${it.name}」已在库 $days 天',
          desc: '如果近半年都没有使用，建议处理掉：转赠、二手出售或回收。',
          actions: const ['mark_discarded', 'log_use', 'view'],
        ));
      }

      final end = warrantyEnd(it);
      if (end != null) {
        final endTime = DateTime.tryParse(end);
        if (endTime != null) {
          // 与 Web 版一致：按自然日计算保修剩余/超出天数
          final now = DateTime.now();
          final diff = DateTime(endTime.year, endTime.month, endTime.day)
              .difference(DateTime(now.year, now.month, now.day))
              .inDays;
          if (diff >= 0 && diff <= 30) {
            out.add(Suggestion(
              key: 'warranty-soon-${it.id}',
              type: 'warranty',
              severity: 'medium',
              itemId: it.id,
              title: '「${it.name}」保修将在 $diff 天后到期',
              desc: '保修截止 $end，到期前记得检查设备状态，必要时申请维修。',
              actions: const ['view'],
            ));
          } else if (diff < 0 && diff >= -60) {
            out.add(Suggestion(
              key: 'warranty-expired-${it.id}',
              type: 'warranty',
              severity: 'low',
              itemId: it.id,
              title: '「${it.name}」保修已过期 ${-diff} 天',
              desc: '保修已于 $end 结束，可以整理并归档相关票据，减少纸质留存。',
              actions: const ['view'],
            ));
          }
        }
      }
    }

    // 重复购买风险：同分类 + 名称去掉括号备注后相同
    final groups = <String, List<Item>>{};
    for (final it in activeItems()) {
      final key = '${it.categoryId}|${stripParens(it.name)}';
      groups.putIfAbsent(key, () => []).add(it);
    }
    groups.forEach((key, list) {
      if (list.length > 1) {
        final name = stripParens(list.first.name);
        out.add(Suggestion(
          key: 'dup-$key',
          type: 'duplicate',
          severity: 'low',
          itemIds: list.map((it) => it.id).toList(),
          name: name,
          title: '「$name」有 ${list.length} 件同类物品',
          desc: '合计 ${list.fold(0, (s, it) => s + it.quantity)} 件，建议保留状态最好的一件，其余处理掉。',
          actions: const ['view'],
        ));
      }
    });

    // 空间超载
    for (final space in spaces) {
      if (space.capacity <= 0) continue;
      final usage = spaceUsage(space.id);
      if (usage.pct != null && usage.pct! >= 90) {
        out.add(Suggestion(
          key: 'space-${space.id}',
          type: 'space',
          severity: usage.pct! >= 100 ? 'high' : 'medium',
          spaceId: space.id,
          title: '${spacePathLabel(space.id, ' · ')} 利用率 ${usage.pct}%',
          desc: '已放 ${usage.count} 件 / 容量 ${usage.capacity}，建议增加收纳单元或精简低频物品。',
          actions: const ['view_space', 'add_container'],
        ));
      }
    }

    // 未归位物品
    final unplaced = unplacedItems();
    if (unplaced.isNotEmpty) {
      final names = unplaced.take(4).map((it) => it.name).join('、');
      out.add(Suggestion(
        key: 'unplaced',
        type: 'unplaced',
        severity: unplaced.length >= 5 ? 'high' : 'medium',
        title: '${unplaced.length} 件物品还没有固定位置',
        desc:
            '$names${unplaced.length > 4 ? ' 等' : ''}，为它们指定收纳位置，下次就能快速找到。',
        actions: const ['open_unplaced'],
      ));
    }

    const weight = {'high': 0, 'medium': 1, 'low': 2};
    out.sort((a, b) => (weight[a.severity] ?? 3).compareTo(weight[b.severity] ?? 3));
    return out;
  }

  /// 日期差按自然日计算
  SiteStats siteStats() {
    final active = activeItems();
    final rooms = rootSpaces();
    final usages = rooms.map((r) => spaceUsage(r.id)).where((u) => u.pct != null).toList();
    final avgPct = usages.isEmpty
        ? 0
        : (usages.fold(0, (s, u) => s + u.pct!) / usages.length).round();
    return SiteStats(
      itemCount: active.length,
      quantity: totalQuantity(active),
      value: totalValue(active),
      unplaced: unplacedItems().length,
      spaceCount: spaces.length,
      roomCount: rooms.length,
      capacity: spaces.fold(0, (s, sp) => s + sp.capacity),
      avgPct: avgPct,
      suggestions: getSuggestions().length,
      images: items.where((it) => it.image != null && it.image!.isNotEmpty).length,
    );
  }
}

/// 去掉名称中的括号备注（重复判定用）
String stripParens(String name) =>
    name.replaceAll(RegExp('（.*?）|\\(.*?\\)'), '').trim();

class CategoryStatBuilder {
  CategoryStatBuilder(this.category);
  final Category category;
  int count = 0;
  int qty = 0;
  double value = 0;
}

class SpaceDepth {
  const SpaceDepth({required this.space, required this.depth});
  final Space space;
  final int depth;
}

class StatusCount {
  const StatusCount({required this.key, required this.label, required this.tone, required this.count});
  final String key;
  final String label;
  final String tone;
  final int count;
}

class UsageRankRow {
  const UsageRankRow({required this.item, required this.uses});
  final Item item;
  final int uses;
}

class YearStat {
  YearStat({required this.year});
  final String year;
  int count = 0;
  double value = 0;
}

class SiteStats {
  const SiteStats({
    required this.itemCount,
    required this.quantity,
    required this.value,
    required this.unplaced,
    required this.spaceCount,
    required this.roomCount,
    required this.capacity,
    required this.avgPct,
    required this.suggestions,
    required this.images,
  });
  final int itemCount;
  final int quantity;
  final double value;
  final int unplaced;
  final int spaceCount;
  final int roomCount;
  final int capacity;
  final int avgPct;
  final int suggestions;
  final int images;
}
