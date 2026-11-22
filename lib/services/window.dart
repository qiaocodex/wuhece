/// 桌面端窗口尺寸/位置记忆（Windows / macOS / Linux）
///
/// 通过条件导入隔离：Web 端使用 [window_stub] 空实现。
library;

export 'window_impl.dart' if (dart.library.html) 'window_stub.dart';
