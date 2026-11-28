/// 页面冒烟测试：保证六大页面在构建时不抛布局/构建异常
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:guiwu/ui/pages/analytics_page.dart';
import 'package:guiwu/ui/pages/backup_data_page.dart';
import 'package:guiwu/ui/pages/backup_page.dart';
import 'package:guiwu/ui/pages/snapshot_page.dart';
import 'package:guiwu/ui/pages/sync_log_page.dart';
import 'package:guiwu/ui/pages/sync_page.dart';
import 'package:guiwu/ui/pages/dashboard_page.dart';
import 'package:guiwu/ui/pages/insights_page.dart';
import 'package:guiwu/ui/pages/items_page.dart';
import 'package:guiwu/ui/pages/settings_page.dart';
import 'package:guiwu/ui/pages/spaces_page.dart';
import 'package:guiwu/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _pump(WidgetTester tester, Widget page) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGuiwuTheme(),
      locale: const Locale('zh', 'CN'),
      home: Scaffold(body: page),
    ),
  );
  await tester.pump();
  return store;
}

void main() {
  testWidgets('总览页构建无异常', (tester) async {
    await _pump(tester, const DashboardPage());
    expect(tester.takeException(), isNull);
  });

  testWidgets('物品库页构建无异常', (tester) async {
    await _pump(tester, const ItemsPage());
    expect(tester.takeException(), isNull);
  });

  testWidgets('空间页构建无异常', (tester) async {
    await _pump(tester, const SpacesPage());
    expect(tester.takeException(), isNull);
  });

  testWidgets('整理建议页构建无异常', (tester) async {
    await _pump(tester, const InsightsPage());
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据分析页构建无异常', (tester) async {
    await _pump(tester, const AnalyticsPage());
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页构建无异常（曾因下拉无界宽度整页空白）', (tester) async {
    await _pump(tester, const SettingsPage());
    expect(tester.takeException(), isNull);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('分类管理'), findsOneWidget);
    expect(find.text('使用偏好'), findsOneWidget);
    expect(find.text('闲置判定天数'), findsOneWidget);
  });

  testWidgets('设置页 @ 390×844 手机尺寸构建无异常', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _pump(tester, const SettingsPage());
    expect(tester.takeException(), isNull);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('闲置判定天数'), findsOneWidget);
  });

  testWidgets('设置页 @ 平板宽屏尺寸构建无异常', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await _pump(tester, const SettingsPage());
    expect(tester.takeException(), isNull);
    expect(find.text('数据管理'), findsOneWidget);
  });

  testWidgets('网盘&备份中心页构建无异常', (tester) async {
    await _pump(tester, const BackupPage());
    expect(tester.takeException(), isNull);
    expect(find.text('网盘同步'), findsOneWidget);
  });

  testWidgets('网盘同步页构建无异常（含百度网盘服务商）', (tester) async {
    await _pump(tester, const SyncPage());
    expect(tester.takeException(), isNull);
    expect(find.text('WebDAV'), findsOneWidget); // 默认服务商
    expect(find.text('同步至'), findsOneWidget);
    expect(find.text('启动自动同步'), findsOneWidget);
  });

  testWidgets('同步记录页空态构建无异常', (tester) async {
    await _pump(tester, const SyncLogPage());
    expect(tester.takeException(), isNull);
    expect(find.text('还没有同步记录'), findsOneWidget);
  });

  testWidgets('历史版本备份页空态构建无异常', (tester) async {
    await _pump(tester, const SnapshotPage());
    expect(tester.takeException(), isNull);
    expect(find.text('还没有快照'), findsOneWidget);
  });

  testWidgets('备份数据页构建无异常', (tester) async {
    await _pump(tester, const BackupDataPage());
    expect(tester.takeException(), isNull);
    expect(find.text('导出完整备份'), findsOneWidget);
  });
}
