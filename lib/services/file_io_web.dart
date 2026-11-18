/// Web 端文件导入导出实现（file_selector_web）
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Web 端始终支持选择文件
bool get filePickSupported => true;

/// 打开文件选择器读取文本内容（取消返回 null）
Future<String?> pickTextFileContent({
  required String label,
  required List<String> extensions,
  required String mime,
}) async {
  final group = XTypeGroup(label: label, extensions: extensions, mimeTypes: [mime]);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  return await file.readAsString();
}

/// 导出文本文件：弹出「另存为」对话框后触发浏览器下载
Future<bool> exportTextFile({
  required String fileName,
  required String content,
  required String mime,
}) async {
  try {
    final ext = fileName.contains('.') ? fileName.split('.').last : 'txt';
    final group = XTypeGroup(label: '数据文件', extensions: [ext], mimeTypes: [mime]);
    final location = await getSaveLocation(suggestedName: fileName, acceptedTypeGroups: [group]);
    if (location == null) return false;
    final file = XFile.fromData(utf8.encode(content), name: fileName, mimeType: mime);
    await file.saveTo(location.path);
    return true;
  } catch (err) {
    return false;
  }
}
