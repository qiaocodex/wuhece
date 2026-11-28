/// 同步服务：配置持久化、冲突判定、上传 / 下载 / 智能同步
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../store/app_store.dart';
import 'snapshot_store.dart';
import 'sync_backend.dart';
import 'sync_log.dart';

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
  static const autoSyncKey = 'guiwu.sync.auto';

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
  ///
  /// 忽略未来时间戳（种子示例数据的「今天 10:24 使用」在上午运行时超前于
  /// 当前时刻，属于示例构造，不参与同步方向判定）。
  static String? localLatestUpdatedAt(AppStore store) {
    final now = DateTime.now().toUtc().toIso8601String();
    String? best;
    for (final it in store.items) {
      if (it.updatedAt.compareTo(now) > 0) continue;
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

  /// 上传备份：先拍本地快照（保留变更前状态），生成 JSON 写入云端并记录标记
  static Future<SyncOutcome> uploadBackup(
    AppStore store,
    SyncBackend backend,
    SharedPreferences prefs, {
    String provider = '',
  }) async {
    final content = store.exportJson();
    try {
      await _takeSnapshot(store);
      await backend.upload(content);
    } on SyncException catch (err) {
      await SyncLog.add(prefs, SyncLogEntry(
        at: DateTime.now().toIso8601String(),
        action: 'upload',
        provider: provider,
        ok: false,
        message: err.message,
      ));
      return SyncOutcome(false, err.message, direction: SyncDirection.upload);
    }
    await _mark(prefs, content);
    await SyncLog.add(prefs, SyncLogEntry(
      at: DateTime.now().toIso8601String(),
      action: 'upload',
      provider: provider,
      ok: true,
      message: '已上传备份到云端（${store.items.length} 件物品）',
    ));
    return SyncOutcome(true, '已上传备份到云端', direction: SyncDirection.upload);
  }

  /// 从云端恢复：下载并覆盖本地数据（恢复前拍快照，内容有效性由 importJson 校验）
  static Future<SyncOutcome> downloadBackup(
    AppStore store,
    SyncBackend backend,
    SharedPreferences prefs, {
    String provider = '',
  }) async {
    final content = await backend.download();
    if (content == null) {
      await SyncLog.add(prefs, SyncLogEntry(
        at: DateTime.now().toIso8601String(),
        action: 'download',
        provider: provider,
        ok: false,
        message: '云端还没有备份',
      ));
      return SyncOutcome(false, '云端还没有备份', direction: SyncDirection.download);
    }
    try {
      await _takeSnapshot(store);
      store.importJson(content);
    } on FormatException catch (err) {
      await SyncLog.add(prefs, SyncLogEntry(
        at: DateTime.now().toIso8601String(),
        action: 'download',
        provider: provider,
        ok: false,
        message: '云端备份无法解析：${err.message}',
      ));
      return SyncOutcome(false, '云端备份无法解析：${err.message}',
          direction: SyncDirection.download);
    }
    await _mark(prefs, content);
    await SyncLog.add(prefs, SyncLogEntry(
      at: DateTime.now().toIso8601String(),
      action: 'download',
      provider: provider,
      ok: true,
      message: '已从云端恢复数据',
    ));
    return SyncOutcome(true, '已从云端恢复数据', direction: SyncDirection.download);
  }

  /// 智能同步：按 [decide] 自动选择方向；返回 null 表示方向为 none。
  /// 当本地与云端都有新变更时（云端非本机上次同步写入），返回 needsDecision
  /// 让 UI 询问用户保留哪边。
  static Future<SyncDecision> smartSync(
    AppStore store,
    SyncBackend backend,
    SharedPreferences prefs, {
    String provider = '',
    String action = 'smart',
  }) async {
    SyncDecision decision;
    try {
      final remote = await backend.download();
      final direction = decide(
        remoteContent: remote,
        store: store,
        lastSyncExportedAt: prefs.getString(lastExportedAtKey),
      );
      switch (direction) {
        case SyncDirection.none:
          decision = SyncDecision.none();
        case SyncDirection.download:
          decision = SyncDecision.done(await downloadBackup(store, backend, prefs, provider: provider));
        case SyncDirection.upload:
          final remoteAt = remote == null ? null : remoteExportedAt(remote);
          final lastSync = prefs.getString(lastExportedAtKey);
          final cloudHasOtherChanges =
              remote != null && (lastSync == null || remoteAt != lastSync);
          if (cloudHasOtherChanges && localLatestUpdatedAt(store) != null) {
            // 云端存在非本机写入的备份：交由用户决定
            decision = SyncDecision.conflict(remoteAt: remoteAt, remoteContent: remote);
          } else {
            decision = SyncDecision.done(await uploadBackup(store, backend, prefs, provider: provider));
          }
      }
    } on SyncException catch (err) {
      await SyncLog.add(prefs, SyncLogEntry(
        at: DateTime.now().toIso8601String(),
        action: action,
        provider: provider,
        ok: false,
        message: err.message,
      ));
      rethrow;
    }
    await SyncLog.add(prefs, SyncLogEntry(
      at: DateTime.now().toIso8601String(),
      action: action,
      provider: provider,
      ok: decision.kind != 'conflict' && decision.outcome.ok,
      message: decision.kind == 'conflict'
          ? '本地与云端都有变更，等待处理'
          : decision.outcome.message,
    ));
    return decision;
  }

  /// 启动自动同步：开关开启且配置完整时静默执行智能同步；冲突不弹窗只记记录。
  /// 返回 decision 供调用方展示（可为 null 表示未触发）。
  static Future<SyncDecision?> maybeAutoSync(AppStore store) async {
    final prefs = store.prefs;
    if (prefs.getBool(autoSyncKey) != true) return null;
    final settings = SyncSettings.load(prefs);
    if (!isProviderConfigured(settings)) return null;
    if (settings.provider == 'boxbook' && (settings.fields['boxbook']?['token'] ?? '').isEmpty) {
      return null;
    }
    if (settings.provider == 'baidu' && (settings.fields['baidu']?['accessToken'] ?? '').isEmpty) {
      return null;
    }
    final backend = buildBackend(settings);
    try {
      return await smartSync(store, backend, prefs,
          provider: settings.provider, action: 'auto');
    } on SyncException {
      return null; // 已记入同步记录，启动阶段不打扰用户
    }
  }

  /// 变更前拍本地快照（尽力而为：介质不可用或测试环境失败时静默跳过）
  static Future<void> _takeSnapshot(AppStore store) async {
    try {
      await SnapshotStore.save(store);
    } catch (_) {
      // 快照失败不阻断同步主流程
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
