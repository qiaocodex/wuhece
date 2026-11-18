/// 原生端（Android/iOS/Windows/macOS）文件导入导出实现
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

/// 当前平台是否支持打开文件选择器导入（file_selector 尚不支持 Android）
bool get filePickSupported => !Platform.isAndroid;

/// 打开文件选择器读取文本内容（取消返回 null）
Future<String?> pickTextFileContent({
  required String label,
  required List<String> extensions,
  required String mime,
}) async {
  if (!filePickSupported) return null;
  final group = XTypeGroup(label: label, extensions: extensions, mimeTypes: [mime]);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  return await file.readAsString();
}

/// 导出文本文件：
/// - 桌面端：保存对话框写入用户选择的位置；
/// - 移动端：调起系统分享面板（可在分享面板中存入文件 / 云盘）。
/// 返回是否成功导出（用户取消返回 false）。
Future<bool> exportTextFile({
  required String fileName,
  required String content,
  required String mime,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Share.shareXFiles(
        [XFile.fromData(utf8.encode(content), name: fileName, mimeType: mime)],
        subject: fileName,
      );
      return true;
    } catch (err) {
      return false;
    }
  }

  final ext = fileName.contains('.') ? fileName.split('.').last : 'txt';
  final group = XTypeGroup(label: '数据文件', extensions: [ext], mimeTypes: [mime]);
  final location = await getSaveLocation(suggestedName: fileName, acceptedTypeGroups: [group]);
  if (location == null) return false;
  await File(location.path).writeAsString(content, flush: true);
  return true;
}
