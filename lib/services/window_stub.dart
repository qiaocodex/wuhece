/// Web 端窗口空实现（浏览器无原生窗口概念）
library;

Future<void> initDesktopWindow(
  Future<void> Function(String json) save,
  String Function() load,
) async {}
