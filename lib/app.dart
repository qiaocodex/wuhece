/// 应用入口：主题、本地化与自适应外壳
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;

import 'store/app_store.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

class GuiwuApp extends StatelessWidget {
  const GuiwuApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final themeMode = switch (store.settings.themeMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        return MaterialApp(
      title: '物盒册 · 个人物品资产与收纳空间管理',
      debugShowCheckedModeBanner: false,
      theme: buildGuiwuTheme(),
      darkTheme: buildGuiwuTheme(dark: true),
      themeMode: themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: HomeShell(store: store),
        );
      },
    );
  }
}
