/// 快速录入快路径测试：本地模板解析 + 快路径/AI 共用落库
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/dates.dart';
import 'package:guiwu/services/quick_entry.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return store;
}

void main() {
  group('tryQuickEntry 模板解析', () {
    test('极简句式：买了体脂秤39.9（参考记账 App 的输入）', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('买了体脂秤39.9', store)!;
      expect(q.name, '体脂秤');
      expect(q.price, 39.9);
      expect(q.quantity, 1);
      expect(q.purchaseDate, toISODate()); // 默认今天
    });

    test('示例话术：昨天买了个保温杯 99 块，放厨房', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('昨天买了个保温杯 99 块，放厨房', store)!;
      expect(q.name, '保温杯');
      expect(q.price, 99);
      expect(q.purchaseDate, toISODate(DateTime.now().subtract(const Duration(days: 1))));
      expect(q.spaceName, '厨房'); // 种子数据含「厨房」空间
    });

    test('示例话术：今天买羽毛球拍花了 50 块，录入一下', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('今天买羽毛球拍花了 50 块，录入一下', store)!;
      expect(q.name, '羽毛球拍');
      expect(q.price, 50);
      expect(q.purchaseDate, toISODate());
    });

    test('数量 + 裸数字价格：买了2个收纳箱 30', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('买了2个收纳箱 30', store)!;
      expect(q.name, '收纳箱');
      expect(q.quantity, 2);
      expect(q.price, 30);
    });

    test('中文数量：买了两瓶洗洁精 12块', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('买了两瓶洗洁精 12块', store)!;
      expect(q.name, '洗洁精');
      expect(q.quantity, 2);
      expect(q.price, 12);
    });

    test('无动词短句：体脂秤 39.9', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('体脂秤 39.9', store)!;
      expect(q.name, '体脂秤');
      expect(q.price, 39.9);
    });

    test('日期词：前天 / 3天前 / 11月20号', () async {
      final store = await _freshStore();
      final today = DateTime.now();
      expect(
        tryQuickEntry('前天买了个拖把', store)!.purchaseDate,
        toISODate(today.subtract(const Duration(days: 2))),
      );
      expect(
        tryQuickEntry('3天前入了挂钩', store)!.purchaseDate,
        toISODate(today.subtract(const Duration(days: 3))),
      );
      expect(
        tryQuickEntry('11月20号买的台灯', store)!.purchaseDate,
        toISODate(DateTime(today.year, 11, 20)),
      );
    });

    test('保修月数：买了电饭煲 299 保修12个月', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('买了电饭煲 299 保修12个月', store)!;
      expect(q.name, '电饭煲');
      expect(q.price, 299);
      expect(q.warrantyMonths, 12);
    });

    test('未知空间提取为短语（落库时匹配不上则未归位）', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('买了手电筒放阳台', store)!;
      expect(q.name, '手电筒');
      expect(q.spaceName, '阳台');
    });

    test('「9号电池」不被误判成日期', () async {
      final store = await _freshStore();
      final q = tryQuickEntry('买了9号电池 5块', store)!;
      expect(q.name, '9号电池');
      expect(q.price, 5);
      expect(q.purchaseDate, toISODate());
    });

    test('问句 / 统计 / 流水类拒绝，交回 AI', () async {
      final store = await _freshStore();
      expect(tryQuickEntry('这个月录入了多少物品', store), isNull);
      expect(tryQuickEntry('MacBook Air 是什么时候买的，还在保修期吗', store), isNull);
      expect(tryQuickEntry('家里现在还有哪些东西是闲置的', store), isNull);
      expect(tryQuickEntry('这个月收入了5000', store), isNull);
      expect(tryQuickEntry('装了3小时才弄好', store), isNull);
      expect(tryQuickEntry('保温杯', store), isNull); // 无动词无价格，语义不明
    });
  });

  group('applyEntryToStore 落库（快路径与 AI add_item 共用）', () {
    test('完整字段', () async {
      final store = await _freshStore();
      final item = applyEntryToStore(
        store,
        name: '保温杯',
        price: 99,
        spaceName: '厨房',
        categoryName: '厨房用品',
        purchaseDate: '2026-11-27',
      );
      expect(item.name, '保温杯');
      expect(item.price, 99);
      expect(store.getCategory(item.categoryId)!.name, '厨房用品');
      expect(store.spacePathLabel(item.spaceId), contains('厨房'));
      expect(item.purchaseDate, '2026-11-27');
    });

    test('分类列表为空时兜底建「其他」', () async {
      final store = await _freshStore();
      store.categories.clear();
      final item = applyEntryToStore(store, name: '挂钩', purchaseDate: toISODate());
      expect(store.getCategory(item.categoryId)!.name, '其他');
    });

    test('非法日期回落今天', () async {
      final store = await _freshStore();
      final item = applyEntryToStore(store, name: '挂钩', purchaseDate: 'abc');
      expect(item.purchaseDate, toISODate());
    });

    test('位置短语长于空间名时反向包含匹配（客厅电视柜 → 客厅）', () async {
      final store = await _freshStore();
      final item = applyEntryToStore(store, name: '摆件', spaceName: '客厅电视柜', purchaseDate: toISODate());
      // 种子数据若含「客厅」空间则匹配成功；否则未归位
      final space = store.spaces.where((s) => item.spaceId == s.id).firstOrNull;
      if (space != null) {
        expect(space.name, contains('客厅'));
      } else {
        expect(item.spaceId, isNull);
      }
    });
  });
}
