/// 核心逻辑单元测试：存储、建议引擎、CSV、JSON 互通
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/csv.dart';
import 'package:guiwu/services/dates.dart';
import 'package:guiwu/services/format.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return store;
}

void main() {
  group('数据层', () {
    test('首次启动载入示例数据', () async {
      final store = await _freshStore();
      expect(store.items.length, 29);
      expect(store.categories.length, 9);
      expect(store.spaces.length, 17);
      expect(store.rootSpaces().length, 6);
    });

    test('新增物品与持久化', () async {
      final store = await _freshStore();
      store.addItem(name: '测试物品', categoryId: 'cat-digital', price: 100, quantity: 2);
      expect(store.items.first.name, '测试物品');
      expect(store.items.first.value, 200);

      // 重新实例化 store，验证已落盘
      final store2 = AppStore(await SharedPreferences.getInstance())..load();
      expect(store2.items.first.name, '测试物品');
    });

    test('分类统计与状态统计', () async {
      final store = await _freshStore();
      final stats = store.categoryStats();
      expect(stats.any((s) => s.category.name == '数码电子'), isTrue);
      final statuses = store.statusStats();
      expect(statuses.firstWhere((s) => s.key == 'lent').count, 1);
    });

    test('删除空间级联，物品变为未归位', () async {
      final store = await _freshStore();
      final descendants = store.collectDescendantIds('sp-closet');
      expect(descendants.length, 2); // 衣柜 + 上层收纳箱
      store.deleteSpace('sp-closet');
      expect(store.spaces.any((s) => s.id == 'sp-closet-top'), isFalse);
      expect(store.items.any((it) => it.spaceId == 'sp-closet-top'), isFalse);
    });

    test('保修截止日计算', () async {
      final store = await _freshStore();
      final item = store.addItem(
        name: '保修机',
        categoryId: 'cat-digital',
        purchaseDate: toISODate(DateTime(2026, 1, 31)),
        warrantyMonths: 1,
      );
      // 与 Web 版行为一致：月末溢出顺延
      expect(store.warrantyEnd(item), '2026-03-03');
    });
  });

  group('整理建议引擎', () {
    test('闲置/借出/未归位规则', () async {
      final store = await _freshStore();
      // 示例数据：帐篷借出 45 天（≥30 → high）、iPhone 闲置 500 天
      final suggestions = store.getSuggestions();
      expect(suggestions.any((s) => s.type == 'lent' && s.severity == 'high'), isTrue);
      expect(suggestions.any((s) => s.type == 'unplaced'), isTrue);
      expect(suggestions.any((s) => s.type == 'duplicate'), isTrue); // 两个保温杯
    });

    test('记录使用后闲置天数归零', () async {
      final store = await _freshStore();
      final item = store.items.first;
      final before = store.daysSinceLastUse(item);
      store.logUsage(item.id, type: 'use');
      expect(store.daysSinceLastUse(store.getItem(item.id)!), 0);
      expect(before, greaterThan(0));
    });
  });

  group('CSV 与备份互通', () {
    test('CSV 往返（引号、逗号、换行）', () {
      const rows = [
        ['名称', '备注'],
        ['MacBook Air', '含,逗号'],
        ['书桌', '含"引号"\n换行'],
      ];
      final text = toCSV(rows);
      final parsed = parseCSV(text);
      expect(parsed.length, 3);
      expect(parsed[1][1], '含,逗号');
      expect(parsed[2][1], '含"引号"\n换行');
    });

    test('CSV 导入映射：列别名 / 状态 / 日期', () async {
      await _freshStore();
      const text = '物品名称,类别,位置,数量,单价,购买日期,状态,标签,备注\n'
          '测试相机,数码电子,书房 / 书架,2,"￥3,500",2024.3.5,闲置,旅行/备用,样机\n';
      final rows = parseCSV(text);
      final drafts = mapCsvRows(rows.first, rows.sublist(1));
      expect(drafts.length, 1);
      final d = drafts.first;
      expect(d.name, '测试相机');
      expect(d.categoryName, '数码电子');
      expect(d.spaceId, 'sp-shelf');
      expect(d.quantity, 2);
      expect(d.price, 3500);
      expect(d.purchaseDate, '2024-03-05');
      expect(d.status, 'idle');
      expect(d.tags, ['旅行', '备用']);
    });

    test('Web 版 JSON 备份导入导出互通', () async {
      final store = await _freshStore();
      final exported = store.exportJson();
      final json = jsonDecode(exported) as Map<String, dynamic>;
      expect(json['app'], 'guiwu');
      expect(json['version'], 1);
      expect((json['items'] as List).length, 29);

      // 字段名与 Web 版一致
      final first = (json['items'] as List).first as Map<String, dynamic>;
      expect(first.keys, containsAll(['name', 'categoryId', 'spaceId', 'tags', 'quantity', 'price', 'status', 'logs', 'createdAt']));

      store.clearAll();
      expect(store.items, isEmpty);
      store.importJson(exported);
      expect(store.items.length, 29);
    });
  });

  group('格式化工具', () {
    test('money 千分位', () {
      expect(money(1299), '¥1,299');
      expect(money(1234567), '¥1,234,567');
      expect(money(100.4), '¥100');
    });

    test('parseTags 去重上限', () {
      expect(parseTags('冬季，通勤、通勤 冬礼'), ['冬季', '通勤', '冬礼']);
    });
  });
}
