/// Phase A 功能测试：GLM 工具执行 / 搜索历史 / AI 页与首启引导冒烟
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/glm_chat.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:guiwu/ui/pages/ai_chat_page.dart';
import 'package:guiwu/ui/shell.dart';
import 'package:guiwu/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return store;
}

void main() {
  group('GLM 工具执行', () {
    test('add_item 完整参数', () async {
      final store = await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      final result = svc.executeTool('add_item', {
        'name': '测试羽毛球拍',
        'price': 50,
        'quantity': 2,
        'category_name': '运动户外',
        'space_name': '厨房',
        'purchase_date': '2026-11-01',
        'tags': ['运动'],
      });
      expect(result, contains('录入成功'));
      final item = store.items.first;
      expect(item.name, '测试羽毛球拍');
      expect(item.price, 50);
      expect(item.quantity, 2);
      expect(item.categoryId, 'cat-sport');
      expect(item.spaceId, 'sp-kitchen');
      expect(item.purchaseDate, '2026-11-01');
    });

    test('add_item 缺名称返回错误提示', () async {
      await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      final result = svc.executeTool('add_item', {'price': 50});
      expect(result, contains('缺少物品名称'));
    });

    test('add_item 空间模糊匹配', () async {
      final store = await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      svc.executeTool('add_item', {'name': '模糊匹配测试', 'space_name': '书'});
      // 候选按种子顺序：书房最先包含「书」
      expect(store.items.first.spaceId, 'sp-study');
    });

    test('query_items count_by_month', () async {
      await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      final result = svc.executeTool('query_items', {'intent': 'count_by_month'});
      expect(result, contains('录入'));
      expect(result, contains('2026-11'));
    });

    test('query_items recent_list 与未知类型', () async {
      await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      expect(svc.executeTool('query_items', {'intent': 'recent_list'}), contains('最近添加'));
      expect(svc.executeTool('query_items', {'intent': 'unknown'}), contains('未知查询类型'));
    });

  });

  group('搜索历史', () {
    test('去重置顶与上限 10 条', () async {
      final store = await _freshStore();
      for (final q in ['a', 'b', 'c', 'a']) {
        store.addSearchHistory(q);
      }
      expect(store.searchHistory(), ['a', 'c', 'b']);
      for (var i = 0; i < 12; i++) {
        store.addSearchHistory('k$i');
      }
      expect(store.searchHistory().length, 10);
      expect(store.searchHistory().first, 'k11');
      store.clearSearchHistory();
      expect(store.searchHistory(), isEmpty);
    });
  });

  group('AI 页与首启引导', () {
    testWidgets('AI 页未配置 key 显示引导卡', (tester) async {
      await _freshStore();
      await tester.pumpWidget(
        MaterialApp(theme: buildGuiwuTheme(), home: const AiChatPage()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('对话式录入物品'), findsOneWidget);
      expect(find.text('去设置页配置 API Key'), findsOneWidget);
    });

    testWidgets('首次启动弹出三选一引导', (tester) async {
      final store = await _freshStore();
      await tester.pumpWidget(
        MaterialApp(theme: buildGuiwuTheme(), home: HomeShell(store: store)),
      );
      await tester.pumpAndSettle();
      expect(find.text('欢迎使用物盒册'), findsOneWidget);
      expect(find.text('载入示例数据'), findsOneWidget);
      expect(find.text('从 Web 版导入'), findsOneWidget);
      expect(find.text('空白开始'), findsOneWidget);
    });
  });
}
