import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/sync/sync_service.dart';
import 'services/window.dart';
import 'store/app_store.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 发布包中把构建异常渲染为可读文本（默认灰屏无从排查）；应用稳定后可移除
  ErrorWidget.builder = (details) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: GColors.dangerWeak,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Text(
                '${details.exceptionAsString()}\n\n${details.stack}',
                style: const TextStyle(
                  color: GColors.danger,
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      );

  final prefs = await SharedPreferences.getInstance();

  // 桌面端：恢复上次窗口尺寸/位置，并挂载自动保存（Web 端为空实现）
  await initDesktopWindow(
    (json) => prefs.setString('guiwu.window', json),
    () => prefs.getString('guiwu.window') ?? '',
  );

  final store = AppStore(prefs)..load();
  runApp(GuiwuApp(store: store));

  // 启动自动同步（开关开启且配置完整时静默智能同步，冲突只记同步记录）
  Future.delayed(const Duration(seconds: 4), () => SyncService.maybeAutoSync(store));
}
