/// 文件导入导出的平台适配层。
///
/// Web / Windows / macOS：file_selector 保存与打开对话框；
/// Android / iOS：导出走系统分享面板（file_selector 尚不支持 Android）。
library;

export 'file_io_native.dart' if (dart.library.html) 'file_io_web.dart';
