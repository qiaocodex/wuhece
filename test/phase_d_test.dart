/// Phase D 功能测试：处置字段兼容 / 处置统计 / 月度资产曲线 / CSV 扩列
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/csv.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return store;
}

void main() {
  group('处置字段兼容', () {
    test('旧版 JSON（无处置字段）导入后为 null', () async {
      final store = await _freshStore();
      final oldWebBackup = jsonEncode({
        'app': 'guiwu',
        'version': 1,
        'items': [
          {
            'id': 'it-old',
            'name': '旧版物品',
            'categoryId': 'cat-other',
            'quantity': 1,
            'price': 100,
            'status': 'in_use',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
          }
        ],
        'categories': [],
        'spaces': [],
        'settings': {},
      });
      store.importJson(oldWebBackup);
      final item = store.items.first;
      expect(item.disposedAt, isNull);
      expect(item.disposalPrice, isNull);
      // 导出时补写出字段（null）
      final reExported = jsonDecode(store.exportJson()) as Map<String, dynamic>;
      final first = (reExported['items'] as List).first as Map<String, dynamic>;
      expect(first.containsKey('disposedAt'), isTrue);
    });
  });

  group('处置统计', () {
    test('件数 / 原值 / 残值 / 回收率', () async {
      final store = await _freshStore();
      store.addItem(
        name: '卖了的手机',
        categoryId: 'cat-digital',
        price: 3000,
        status: 'discarded',
        disposedAt: '2026-10-15',
        disposalPrice: 1200,
      );
      store.addItem(
        name: '丢掉的旧椅子',
        categoryId: 'cat-home',
        price: 200,
        status: 'discarded',
        disposedAt: '2026-11-01',
      );
      store.addItem(name: '还在用的桌子', categoryId: 'cat-home', price: 500);
      final stats = store.disposalStats();
      expect(stats.count, 2);
      expect(stats.originalValue, 3200);
      expect(stats.salvage, 1200);
      expect(stats.recoveryPct, 40); // 1200 / 3000
    });
  });

  group('月度资产曲线', () {
    test('累计购入 − 处置回收，逐月补齐', () async {
      final store = await _freshStore();
      store.clearAll(); // 清掉种子数据，避免干扰起点月份
      store.addItem(
        name: '一月买的',
        categoryId: 'cat-other',
        price: 100,
        purchaseDate: '2026-01-10',
      );
      store.addItem(
        name: '三月买的',
        categoryId: 'cat-other',
        price: 300,
        purchaseDate: '2026-03-05',
      );
      store.addItem(
        name: '三月处置的',
        categoryId: 'cat-other',
        price: 200,
        purchaseDate: '2026-01-20',
        status: 'discarded',
        disposedAt: '2026-03-20',
        disposalPrice: 80,
      );
      final series = store.monthlyAssetSeries();
      double valueAt(String month) =>
          series.firstWhere((p) => p.month == month).cumulativeInvested;
      expect(series.first.month, '2026-01');
      expect(valueAt('2026-01'), 300); // 100 + 200
      expect(valueAt('2026-02'), 300); // 无变化
      expect(valueAt('2026-03'), 300 - 80 + 300); // 回收 80 + 购入 300
      // 曲线到当前月为止连续
      expect(series.last.month, '2026-11');
    });
  });

  group('CSV 处置列', () {
    test('导出含处置列，导入可解析', () async {
      final store = await _freshStore();
      store.addItem(
        name: '处置测试品',
        categoryId: 'cat-other',
        price: 100,
        status: 'discarded',
        disposedAt: '2026-09-01',
        disposalPrice: 30,
      );
      final csv = buildItemsCsv();
      expect(csv, contains('处置日期'));
      expect(csv, contains('残值(元)'));

      final rows = parseCSV(csv);
      final drafts = mapCsvRows(rows.first, rows.sublist(1));
      final d = drafts.firstWhere((r) => r.name == '处置测试品');
      expect(d.disposedAt, '2026-09-01');
      expect(d.disposalPrice, 30);
    });
  });
}
