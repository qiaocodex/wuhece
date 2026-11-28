/// 同步操作记录：每次同步/上传/恢复/测试都留痕，供「同步记录」页回溯
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一条同步记录
class SyncLogEntry {
  const SyncLogEntry({
    required this.at,
    required this.action,
    required this.provider,
    required this.ok,
    required this.message,
  });

  /// 操作时间（本地 ISO）
  final String at;

  /// smart / upload / download / test / restore / auto
  final String action;

  /// 服务商标识（webdav / baidu / …）
  final String provider;

  final bool ok;
  final String message;

  Map<String, dynamic> toJson() => {'at': at, 'action': action, 'provider': provider, 'ok': ok, 'message': message};

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => SyncLogEntry(
        at: json['at']?.toString() ?? '',
        action: json['action']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        ok: json['ok'] == true,
        message: json['message']?.toString() ?? '',
      );
}

/// 同步记录存取（SharedPreferences，最新在前，上限 100 条）
class SyncLog {
  SyncLog._();

  static const key = 'guiwu.sync.log';
  static const _maxEntries = 100;

  /// 动作中文名（同步记录页展示）
  static String actionLabel(String action) => switch (action) {
        'smart' => '智能同步',
        'upload' => '上传备份',
        'download' => '云端恢复',
        'test' => '测试连接',
        'restore' => '快照恢复',
        'auto' => '启动自动同步',
        _ => action,
      };

  static List<SyncLogEntry> load(SharedPreferences prefs) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => SyncLogEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(SharedPreferences prefs, SyncLogEntry entry) async {
    final list = List<SyncLogEntry>.of(load(prefs))..insert(0, entry);
    if (list.length > _maxEntries) list.removeRange(_maxEntries, list.length);
    await prefs.setString(key, jsonEncode([for (final e in list) e.toJson()]));
  }
}
