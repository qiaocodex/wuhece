/// 本地快照（历史版本备份）：每次云同步变更数据前自动留存一份当前数据，
/// 供随时恢复；索引存 SharedPreferences，内容存应用文档目录（Web 端存
/// localStorage 并限制份数）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../store/app_store.dart';
import 'snapshot_io_native.dart' if (dart.library.html) 'snapshot_io_web.dart' as snapshot_io;

/// 快照存储介质（native=文档目录文件 / web=localStorage，测试可注入内存实现）
export 'snapshot_io_native.dart' if (dart.library.html) 'snapshot_io_web.dart'
    show SnapshotStorage, getSnapshotStorage, snapshotCapacity;

/// 快照索引项
class SnapshotIndexEntry {
  const SnapshotIndexEntry({required this.id, required this.at, required this.itemCount, required this.bytes});

  final String id;
  final String at; // 本地 ISO 时间
  final int itemCount;
  final int bytes;

  Map<String, dynamic> toJson() => {'id': id, 'at': at, 'itemCount': itemCount, 'bytes': bytes};

  factory SnapshotIndexEntry.fromJson(Map<String, dynamic> json) => SnapshotIndexEntry(
        id: json['id']?.toString() ?? '',
        at: json['at']?.toString() ?? '',
        itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );
}

/// 本地快照库
class SnapshotStore {
  SnapshotStore._();

  static const key = 'guiwu.sync.snapshots';

  /// 用给定的存储介质创建（测试用内存实现；缺省按平台取实现）
  static snapshot_io.SnapshotStorage storage([snapshot_io.SnapshotStorage? custom]) => custom ?? snapshot_io.getSnapshotStorage();

  static List<SnapshotIndexEntry> list(SharedPreferences prefs) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((m) => SnapshotIndexEntry.fromJson(Map<String, dynamic>.from(m))).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 拍摄当前数据快照，返回快照 id；存储失败抛出（调用方决定是否忽略）
  static Future<String> save(AppStore store, {snapshot_io.SnapshotStorage? storageOverride}) async {
    final content = store.exportJson();
    final id = 'snap-${DateTime.now().millisecondsSinceEpoch}';
    await (storageOverride ?? storage()).write(id, content);
    final prefs = store.prefs;
    final entry = SnapshotIndexEntry(
      id: id,
      at: DateTime.now().toIso8601String(),
      itemCount: store.items.length,
      bytes: utf8.encode(content).length,
    );
    final list0 = List<SnapshotIndexEntry>.of(list(prefs))..insert(0, entry);
    await _persist(prefs, list0);
    await _trim(prefs, storageOverride);
    return id;
  }

  /// 读取快照内容（不存在返回 null）
  static Future<String?> read(snapshot_io.SnapshotStorage? storageOverride, SharedPreferences prefs, String id) async {
    final exists = list(prefs).any((e) => e.id == id);
    if (!exists) return null;
    return (storageOverride ?? storage()).read(id);
  }

  /// 恢复快照到当前数据（覆盖式）；成功返回 true
  static Future<bool> restore(
    AppStore store,
    SharedPreferences prefs,
    String id, {
    snapshot_io.SnapshotStorage? storageOverride,
  }) async {
    final content = await read(storageOverride, prefs, id);
    if (content == null) return false;
    try {
      store.importJson(content);
    } on FormatException {
      return false;
    }
    return true;
  }

  static Future<void> delete(SharedPreferences prefs, String id, {snapshot_io.SnapshotStorage? storageOverride}) async {
    final rest = List<SnapshotIndexEntry>.of(list(prefs))..removeWhere((e) => e.id == id);
    await _persist(prefs, rest);
    await (storageOverride ?? storage()).delete(id);
  }

  /// 超出容量时从最旧开始清理（同时删除存储内容）
  static Future<void> _trim(SharedPreferences prefs, snapshot_io.SnapshotStorage? storageOverride) async {
    final cap = snapshot_io.snapshotCapacity;
    final list0 = list(prefs);
    if (list0.length <= cap) return;
    final overflow = list0.sublist(cap);
    await _persist(prefs, list0.sublist(0, cap));
    final impl = storageOverride ?? storage();
    for (final e in overflow) {
      await impl.delete(e.id);
    }
  }

  static Future<void> _persist(SharedPreferences prefs, List<SnapshotIndexEntry> entries) {
    return prefs.setString(key, jsonEncode([for (final e in entries) e.toJson()]));
  }
}
