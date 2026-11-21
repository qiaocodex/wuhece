/// Phase C 功能测试：标签管理 / 深色主题 / 新页面冒烟
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/models/models.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:guiwu/ui/pages/settings_page.dart';
import 'package:guiwu/ui/pages/tags_page.dart';
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
  group('标签管理', () {
    test('tagStats 计数并按频次降序', () async {
      final store = await _freshStore();
      store.addItem(name: '测试A', categoryId: 'cat-other', tags: ['测试标签X', '测试标签共用']);
      store.addItem(name: '测试B', categoryId: 'cat-other', tags: ['测试标签共用']);
      final stats = store.tagStats();
      expect(stats['测试标签共用'], 2);
      expect(stats['测试标签X'], 1);
      // 频次降序
      final keys = stats.keys.toList();
      expect(keys.indexOf('测试标签共用'), lessThan(keys.indexOf('测试标签X')));
    });

    test('renameTag 批量重命名并去重', () async {
      final store = await _freshStore();
      store.addItem(name: '测试A', categoryId: 'cat-other', tags: ['测试标签X', '测试独有Y']);
      store.addItem(name: '测试B', categoryId: 'cat-other', tags: ['测试标签X']);
      store.renameTag('测试标签X', '测试独有Y');
      Item byName(String n) => store.items.firstWhere((it) => it.name == n);
      expect(byName('测试A').tags, ['测试独有Y']);
      expect(byName('测试B').tags, ['测试独有Y']);
      expect(store.tagStats()['测试标签X'], isNull);
    });

    test('removeTag 从所有物品移除', () async {
      final store = await _freshStore();
      store.addItem(name: '测试A', categoryId: 'cat-other', tags: ['测试标签删除']);
      store.addItem(name: '测试B', categoryId: 'cat-other', tags: ['测试标签删除', '测试保留Z']);
      store.removeTag('测试标签删除');
      Item byName(String n) => store.items.firstWhere((it) => it.name == n);
      expect(byName('测试A').tags, isEmpty);
      expect(byName('测试B').tags, ['测试保留Z']);
    });
  });

  group('深色主题', () {
    test('亮暗色板不同且已注册到 ThemeData', () {
      final light = buildGuiwuTheme();
      final dark = buildGuiwuTheme(dark: true);
      final lc = light.extension<GuiwuThemeColors>()!.c;
      final dc = dark.extension<GuiwuThemeColors>()!.c;
      expect(lc.bg != dc.bg, isTrue);
      expect(dc.bg, kDarkColors.bg);
      expect(dark.scaffoldBackgroundColor, kDarkColors.bg);
      expect(light.scaffoldBackgroundColor, kLightColors.bg);
    });

    testWidgets('暗色主题下设置页构建无异常', (tester) async {
      final store = await _freshStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGuiwuTheme(dark: true),
          home: const Scaffold(body: SettingsPage()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('云同步'), findsOneWidget);
      expect(find.text('AI 助手'), findsOneWidget);
    });

    testWidgets('标签页空态构建无异常', (tester) async {
      final store = await _freshStore();
      store.clearAll();
      await tester.pumpWidget(
        MaterialApp(theme: buildGuiwuTheme(), home: const Scaffold(body: TagsPage())),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('还没有标签'), findsOneWidget);
    });
  });
}
