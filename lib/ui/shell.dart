/// 自适应外壳：宽屏侧栏导航，窄屏顶部栏 + 底部导航（对应 Web 版 app.js 的 shell）
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/file_io.dart' as file_io;
import '../store/app_store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pages/ai_chat_page.dart';
import 'pages/analytics_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/insights_page.dart';
import 'pages/item_form.dart';
import 'pages/items_page.dart';
import 'pages/settings_page.dart';
import 'pages/spaces_page.dart';

class _TabMeta {
  const _TabMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _tabs = [
  _TabMeta('总览', Icons.home_outlined),
  _TabMeta('物品库', Icons.inventory_2_outlined),
  _TabMeta('空间', Icons.space_dashboard_outlined),
  _TabMeta('整理建议', Icons.auto_awesome_outlined),
  _TabMeta('数据分析', Icons.bar_chart),
];

/// 跨页导航（页面卡片里的跳转链接用）
class ShellNav extends InheritedWidget {
  const ShellNav({
    super.key,
    required this.go,
    required this.searchItems,
    required super.child,
  });

  final void Function(int index) go;
  final void Function(String query) searchItems;

  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(covariant ShellNav oldWidget) => false;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final AppStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _firstRunHandled = false;
  final GlobalKey<ItemsPageState> _itemsKey = GlobalKey();

  List<Widget> _pages(GlobalKey<ItemsPageState> itemsKey) => [
        const DashboardPage(),
        ItemsPage(key: itemsKey),
        const SpacesPage(),
        const InsightsPage(),
        const AnalyticsPage(),
      ];

  void _go(int index) => setState(() => _index = index);

  void _searchItems(String query) {
    _itemsKey.currentState?.applySearch(query);
    setState(() => _index = 1);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  void _openAiChat() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AiChatPage()),
    );
  }

  /// 首次启动：三选一（示例数据 / 从 Web 版导入 / 空白开始）
  void _maybeFirstRun() {
    if (_firstRunHandled) return;
    _firstRunHandled = true;
    final store = widget.store;
    if (store.seenWelcome) return;

    showResponsive<String>(
      context,
      builder: (_) => const _FirstRunDialog(),
    ).then((choice) {
      switch (choice) {
        case 'import':
          _showImportSheet();
        case 'blank':
          store.clearAll();
          if (mounted) toast(context, '已切换为空白物品库，开始录入吧');
        default:
          if (mounted) toast(context, '示例数据已就绪，点开物品看看吧');
      }
      store.markWelcomeSeen();
    });
  }

  Future<void> _showImportSheet() async {
    final content = await showResponsive<String>(
      context,
      builder: (_) => const _ImportJsonSheet(),
    );
    if (content == null || !mounted) return;
    try {
      widget.store.importJson(content);
      toast(context, '导入成功，欢迎使用物盒册');
    } catch (err) {
      toast(
        context,
        err is FormatException ? '导入失败：${err.message}' : '导入失败：文件内容无法解析',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFirstRun());

    final wide = isWide(context);
    final body = IndexedStack(index: _index, children: _pages(_itemsKey));

    return ShellNav(
      go: _go,
      searchItems: _searchItems,
      child: CallbackShortcuts(
        bindings: {
          // Ctrl/Cmd+N 新增物品；Ctrl/Cmd+F 搜索；Ctrl/Cmd+1~5 切换页面；Ctrl/Cmd+, 设置
          SingleActivator(LogicalKeyboardKey.keyN, control: true): () => openItemForm(context),
          SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => openItemForm(context),
          SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _itemsKey.currentState?.focusSearch(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _itemsKey.currentState?.focusSearch(),
          SingleActivator(LogicalKeyboardKey.comma, control: true): _openSettings,
          SingleActivator(LogicalKeyboardKey.comma, meta: true): _openSettings,
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _go(0),
          const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => _go(0),
          const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _go(1),
          const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => _go(1),
          const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _go(2),
          const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => _go(2),
          const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _go(3),
          const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => _go(3),
          const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => _go(4),
          const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () => _go(4),
        },
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => wide
              ? Scaffold(body: Row(children: [_buildSidebar(context), _vLine(), Expanded(child: body)]))
              : Scaffold(
                  appBar: _mobileAppBar(context),
                  body: body,
                  bottomNavigationBar: _bottomNav(context),
                ),
        ),
      ),
    );
  }

  Widget _vLine() => Container(width: 1, color: context.gc.line);

  Widget _brand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: context.gc.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.inventory_2_outlined, size: 17, color: Colors.white),
        ),
        SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('物盒册', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.gc.ink, height: 1.1)),
            Text(
              'ASSET & SPACE',
              style: TextStyle(fontSize: 8.5, letterSpacing: 1.1, color: context.gc.muted2, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _mobileAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: context.gc.bg,
      surfaceTintColor: context.gc.bg,
      scrolledUnderElevation: 0,
      title: _brand(),
      actions: [
        IconButton(
          icon: const Icon(Icons.smart_toy_outlined, size: 20),
          tooltip: 'AI 助手',
          onPressed: _openAiChat,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: '设置',
          onPressed: _openSettings,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            onPressed: () => openItemForm(context),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('记物品'),
          ),
        ),
      ],
    );
  }

  Widget _bottomNav(BuildContext context) {
    final count = widget.store.getSuggestions().length;
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: _go,
      height: 64,
      destinations: [
        for (var i = 0; i < _tabs.length; i++)
          NavigationDestination(
            icon: _tabIcon(i, count, selected: false),
            selectedIcon: _tabIcon(i, count, selected: true),
            label: _tabs[i].label,
          ),
      ],
    );
  }

  Widget _tabIcon(int index, int count, {required bool selected}) {
    final icon = Icon(
      selected ? _filledIcon(_tabs[index].icon) : _tabs[index].icon,
      size: 21,
    );
    if (index == 3 && count > 0) {
      return Badge(
        label: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, height: 1),
        ),
        backgroundColor: context.gc.danger,
        textColor: Colors.white,
        smallSize: 16,
        offset: const Offset(3, -3),
        child: icon,
      );
    }
    return icon;
  }

  IconData _filledIcon(IconData outlined) => switch (outlined) {
        Icons.home_outlined => Icons.home,
        Icons.inventory_2_outlined => Icons.inventory_2,
        Icons.space_dashboard_outlined => Icons.space_dashboard,
        Icons.auto_awesome_outlined => Icons.auto_awesome,
        Icons.bar_chart => Icons.bar_chart,
        _ => outlined,
      };

  Widget _buildSidebar(BuildContext context) {
    final count = widget.store.getSuggestions().length;
    return Container(
      width: 224,
      color: context.gc.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: _brand(),
            ),
            const _SidebarLabel('工作台'),
            for (var i = 0; i < _tabs.length; i++)
              _SidebarItem(
                meta: _tabs[i],
                active: _index == i,
                badgeCount: i == 3 ? count : 0,
                onTap: () => _go(i),
              ),
            const _SidebarLabel('管理'),
            _SidebarItem(
              meta: const _TabMeta('AI 助手', Icons.smart_toy_outlined),
              active: false,
              onTap: _openAiChat,
            ),
            _SidebarItem(
              meta: const _TabMeta('设置', Icons.settings_outlined),
              active: false,
              onTap: _openSettings,
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('本地数据', style: TextStyle(fontSize: 11.5, color: context.gc.muted2)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '数据保存在本机',
                    style: TextStyle(fontSize: 11, color: context.gc.muted2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, letterSpacing: 1.5, color: context.gc.muted2, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.meta, required this.active, required this.onTap, this.badgeCount = 0});

  final _TabMeta meta;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: active ? context.gc.primaryWeak : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(meta.icon, size: 18, color: active ? context.gc.primary : context.gc.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    meta.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? context.gc.primary : context.gc.inkSoft,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  MiniBadge(
                    label: badgeCount > 99 ? '99+' : '$badgeCount',
                    color: context.gc.danger,
                    bg: context.gc.dangerWeak,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------- 首次启动引导 ------------------------- */

class _FirstRunDialog extends StatelessWidget {
  const _FirstRunDialog();

  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, String title, String desc, String value, {bool recommended = false}) {
      return InkWell(
        onTap: () => Navigator.pop(context, value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.gc.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.gc.lineStrong),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.gc.primaryWeak,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: context.gc.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.gc.ink),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 6),
                          const MiniBadge(label: '推荐'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(desc, style: TextStyle(fontSize: 11.5, color: context.gc.muted, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: context.gc.muted2),
            ],
          ),
        ),
      );
    }

    return FormScaffold(
      title: '欢迎使用物盒册',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '首次启动，选择如何开始使用：',
            style: TextStyle(fontSize: 12.5, color: context.gc.muted),
          ),
          const SizedBox(height: 12),
          option(
            Icons.inventory_2_outlined,
            '载入示例数据',
            '预置 29 件物品演示，先体验全部功能',
            'demo',
            recommended: true,
          ),
          const SizedBox(height: 10),
          option(
            Icons.upload_outlined,
            '从 Web 版导入',
            '已在浏览器版录入了数据？导入 JSON 备份',
            'import',
          ),
          const SizedBox(height: 10),
          option(
            Icons.add_circle_outline,
            '空白开始',
            '不需要示例数据，从零开始记录',
            'blank',
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ImportJsonSheet extends StatefulWidget {
  const _ImportJsonSheet();

  @override
  State<_ImportJsonSheet> createState() => _ImportJsonSheetState();
}

class _ImportJsonSheetState extends State<_ImportJsonSheet> {
  final _contentCtrl = TextEditingController();
  bool _filePickSupported = false;

  @override
  void initState() {
    super.initState();
    _filePickSupported = file_io.filePickSupported;
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: '从 Web 版导入备份',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _contentCtrl.text),
          child: const Text('导入'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '在浏览器版「设置 → 导出完整备份」下载 JSON 文件，'
            '然后在这里选择该文件，或把文件内容粘贴到下方。',
            style: TextStyle(fontSize: 12, color: context.gc.muted, height: 1.6),
          ),
          const SizedBox(height: 14),
          FormField2(
            label: '备份 JSON 内容',
            child: TextField(
              controller: _contentCtrl,
              maxLines: 8,
              minLines: 6,
              decoration: const InputDecoration(hintText: '粘贴 JSON 备份内容，或点击下方按钮选择文件'),
            ),
          ),
          const SizedBox(height: 12),
          if (_filePickSupported)
            OutlinedButton.icon(
              onPressed: () async {
                final content = await file_io.pickTextFileContent(
                  label: 'JSON 备份',
                  extensions: ['json'],
                  mime: 'application/json',
                );
                if (content != null) {
                  setState(() => _contentCtrl.text = content);
                }
              },
              icon: const Icon(Icons.folder_open_outlined, size: 14),
              label: const Text('选择备份文件'),
            )
          else
            Text(
              '手机端不支持直接选择文件：请把 JSON 内容复制后粘贴到上方文本框',
              style: TextStyle(fontSize: 11, color: context.gc.muted2),
            ),
        ],
      ),
    );
  }
}
