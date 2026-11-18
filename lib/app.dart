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
    return MaterialApp(
      title: '归物 · 让每件物品都有归处',
      debugShowCheckedModeBanner: false,
      theme: buildGuiwuTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: HomeShell(store: store),
    );
  }
}
