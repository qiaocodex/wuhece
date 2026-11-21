/// 同步服务：配置持久化、冲突判定、上传 / 下载 / 智能同步
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../store/app_store.dart';
import 'sync_backend.dart';

/// 判定出的同步方向
enum SyncDirection { upload, download, none }

/// 同步执行结果
class SyncOutcome {
  const SyncOutcome(this.ok, this.message, {this.direction});
  final bool ok;
  final String message;
  final SyncDirection? direction;
}

class SyncService {
  SyncService._();

  static const configKey = 'guiwu.sync.config';
  static const lastAtKey = 'guiwu.sync.lastAt';
  static const lastExportedAtKey = 'guiwu.sync.exportedAt';

  /// 读取配置
  static SyncConfig? loadConfig(SharedPreferences prefs) {
    final raw = prefs.getString(configKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? SyncConfig.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(SharedPreferences prefs, SyncConfig config) {
    return prefs.setString(configKey, jsonEncode(config.toJson()));
  }

  /// 最近一次同步时间（ISO），未同步过返回 null
  static String? lastSyncAt(SharedPreferences prefs) => prefs.getString(lastAtKey);

  /// 本地数据的最近变更时间（取所有物品 updatedAt 最大值）
  static String? localLatestUpdatedAt(AppStore store) {
    String? best;
    for (final it in store.items) {
      if (it.updatedAt.compareTo(best ?? '') > 0) best = it.updatedAt;
    }
    return best;
  }

  /// 从备份 JSON 中取出 exportedAt
  static String? remoteExportedAt(String remoteJson) {
    try {
      final data = jsonDecode(remoteJson);
      return data is Map ? data['exportedAt']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  /// 判定同步方向。
  ///
  /// 规则：
  /// - 云端无备份 → 上传（首次同步）
  /// - 云端备份就是上次同步写入的（exportedAt 匹配）且本地无更新 → 无需同步
  /// - 本地最近变更晚于云端备份时间 → 上传
  /// - 否则 → 下载（云端较新）
  static SyncDirection decide({
    required String? remoteContent,
    required AppStore store,
    required String? lastSyncExportedAt,
  }) {
    if (remoteContent == null || remoteContent.isEmpty) {
      return SyncDirection.upload;
    }
    final remoteAt = remoteExportedAt(remoteContent);
    if (remoteAt == null) return SyncDirection.upload; // 远端内容不可识别

    final localAt = localLatestUpdatedAt(store);
    final syncedAt = lastSyncExportedAt;
    if (syncedAt != null &&
        remoteAt == syncedAt &&
        (localAt == null || localAt.compareTo(syncedAt) <= 0)) {
      return SyncDirection.none;
    }
    if (localAt != null && localAt.compareTo(remoteAt) > 0) {
      return SyncDirection.upload;
    }
    return SyncDirection.download;
  }

  /// 上传备份：生成 JSON 写入云端，并记录同步标记
  static Future<SyncOutcome> uploadBackup(
    AppStore store,
    SyncBackend backend,
    SharedPreferences prefs,
  ) async {
    final content = store.exportJson();
    try {
      await backend.upload(content);
    } on SyncException catch (err) {
      return SyncOutcome(false, err.message, direction: SyncDirection.upload);
    }
    await _mark(prefs, content);
    return SyncOutcome(true, '已上传备份到云端', direction: SyncDirection.upload);
  }

  /// 从云端恢复：下载并覆盖本地数据（内容有效性由 importJson 校验）
  static Future<SyncOutcome> downloadBackup(
    AppStore store,
    SyncBackend backend,
    SharedPreferences prefs,
  ) async {
    final content = await backend.download();
    if (content == null) {
      return SyncOutcome(false, '云端还没有备份', direction: SyncDirection.download);
    }
    try {
      store.importJson(content);
    } on FormatException catch (err) {
      return SyncOutcome(false, '云端备份无法解析：${err.message}',
          direction: SyncDirection.download);
    }
    await _mark(prefs, content);
    return SyncOutcome(true, '已从云端恢复数据', direction: SyncDirection.download);
  }

  /// 智能同步：按 [decide] 自动选择方向；返回 null 表示方向为 none。
  /// 当本地与云端都有新变更时（云端非本机上次同步写入），返回 needsDecision
  /// 让 UI 询问用户保留哪边。
  static Future<SyncDecision> smartSync(
    AppStore store,
    SyncBackend backend,
    SharedPreferences prefs,
  ) async {
    final remote = await backend.download();
    final direction = decide(
      remoteContent: remote,
      store: store,
      lastSyncExportedAt: prefs.getString(lastExportedAtKey),
    );
    switch (direction) {
      case SyncDirection.none:
        return SyncDecision.none();
      case SyncDirection.download:
        final outcome = await downloadBackup(store, backend, prefs);
        return SyncDecision.done(outcome);
      case SyncDirection.upload:
        final remoteAt = remote == null ? null : remoteExportedAt(remote);
        final lastSync = prefs.getString(lastExportedAtKey);
        final cloudHasOtherChanges =
            remote != null && (lastSync == null || remoteAt != lastSync);
        if (cloudHasOtherChanges && localLatestUpdatedAt(store) != null) {
          // 云端存在非本机写入的备份：交由用户决定
          return SyncDecision.conflict(remoteAt: remoteAt, remoteContent: remote);
        }
        final outcome = await uploadBackup(store, backend, prefs);
        return SyncDecision.done(outcome);
    }
  }

  static Future<void> _mark(SharedPreferences prefs, String content) async {
    final exportedAt = remoteExportedAt(content) ?? DateTime.now().toUtc().toIso8601String();
    await prefs.setString(lastAtKey, DateTime.now().toUtc().toIso8601String());
    await prefs.setString(lastExportedAtKey, exportedAt);
  }
}

/// 智能同步的结果
class SyncDecision {
  SyncDecision.none()
      : kind = 'none',
        outcome = const SyncOutcome(true, '本地与云端数据一致'),
        remoteAt = null,
        remoteContent = null;

  SyncDecision.done(this.outcome)
      : kind = 'done',
        remoteAt = null,
        remoteContent = null;

  SyncDecision.conflict({required this.remoteAt, required this.remoteContent})
      : kind = 'conflict',
        outcome = const SyncOutcome(false, '本地与云端都有变更');

  /// none / done / conflict
  final String kind;
  final SyncOutcome outcome;
  final String? remoteAt;
  final String? remoteContent;
}
