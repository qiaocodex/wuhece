/// 自适应外壳：宽屏侧栏导航，窄屏顶部栏 + 底部导航（对应 Web 版 app.js 的 shell）
library;

import 'package:material_ui/material_ui.dart';

import '../store/app_store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
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
  bool _welcomeShown = false;
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

  void _maybeShowWelcome() {
    if (_welcomeShown) return;
    _welcomeShown = true;
    final store = widget.store;
    if (!store.seenWelcome && store.items.isNotEmpty) {
      store.markWelcomeSeen();
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) toast(context, '示例数据已就绪，点开物品看看吧');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWelcome());

    final wide = isWide(context);
    final body = IndexedStack(index: _index, children: _pages(_itemsKey));

    return ShellNav(
      go: _go,
      searchItems: _searchItems,
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
    );
  }

  Widget _vLine() => Container(width: 1, color: GColors.line);

  Widget _brand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: GColors.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.inventory_2_outlined, size: 17, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('归物', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: GColors.ink, height: 1.1)),
            Text(
              'ASSET & SPACE',
              style: TextStyle(fontSize: 8.5, letterSpacing: 1.1, color: GColors.muted2, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _mobileAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: GColors.bg,
      surfaceTintColor: GColors.bg,
      scrolledUnderElevation: 0,
      title: _brand(),
      actions: [
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
        backgroundColor: GColors.danger,
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
      color: GColors.surface,
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
              meta: const _TabMeta('设置', Icons.settings_outlined),
              active: false,
              onTap: _openSettings,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Text('本地数据', style: TextStyle(fontSize: 11.5, color: GColors.muted2)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '数据保存在本机',
                    style: TextStyle(fontSize: 11, color: GColors.muted2),
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
        style: const TextStyle(fontSize: 10.5, letterSpacing: 1.5, color: GColors.muted2, fontWeight: FontWeight.w600),
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
        color: active ? GColors.primaryWeak : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(meta.icon, size: 18, color: active ? GColors.primary : GColors.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    meta.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? GColors.primary : GColors.inkSoft,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  MiniBadge(
                    label: badgeCount > 99 ? '99+' : '$badgeCount',
                    color: GColors.danger,
                    bg: GColors.dangerWeak,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
