/// Phase B 功能测试：同步方向判定 / 上传恢复闭环 / 冲突
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/sync/sync_backend.dart';
import 'package:guiwu/services/sync/sync_service.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假后端：内存中的远端内容
class FakeBackend implements SyncBackend {
  FakeBackend([this.remote]);
  String? remote;
  bool shouldThrow = false;
  String? throwMessage = '无法连接服务器';

  @override
  Future<void> testConnection() async {
    if (shouldThrow) throw SyncException(throwMessage!);
  }

  @override
  Future<void> upload(String content) async {
    if (shouldThrow) throw SyncException(throwMessage!);
    remote = content;
  }

  @override
  Future<String?> download() async {
    if (shouldThrow) throw SyncException(throwMessage!);
    return remote;
  }
}

Future<(AppStore, SharedPreferences)> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return (store, prefs);
}

void main() {
  group('同步方向判定', () {
    test('云端为空 → 上传', () async {
      final (store, prefs) = await _fresh();
      final d = SyncService.decide(
        remoteContent: null,
        store: store,
        lastSyncExportedAt: prefs.getString(SyncService.lastExportedAtKey),
      );
      expect(d, SyncDirection.upload);
    });

    test('上传后再次判定 → none（已一致）', () async {
      final (store, prefs) = await _fresh();
      final backend = FakeBackend();
      final outcome = await SyncService.uploadBackup(store, backend, prefs);
      expect(outcome.ok, isTrue);
      final lastSync = prefs.getString(SyncService.lastExportedAtKey);
      final d = SyncService.decide(
        remoteContent: backend.remote,
        store: store,
        lastSyncExportedAt: lastSync,
      );
      expect(d, SyncDirection.none);
    });

    test('本地有新变更 → 上传', () async {
      final (store, prefs) = await _fresh();
      final backend = FakeBackend();
      await SyncService.uploadBackup(store, backend, prefs);
      // 上传后本地再修改一件物品
      store.patchItem(store.items.first.id, (item) => item.quantity = 99);
      final d = SyncService.decide(
        remoteContent: backend.remote,
        store: store,
        lastSyncExportedAt: prefs.getString(SyncService.lastExportedAtKey),
      );
      expect(d, SyncDirection.upload);
    });

    test('云端较新 → 下载', () async {
      final (store, _) = await _fresh();
      final remote = jsonEncode({
        'app': 'guiwu',
        'exportedAt': '2099-01-01T00:00:00.000Z',
        'items': [],
        'categories': [],
        'spaces': [],
        'settings': {},
      });
      final d = SyncService.decide(
        remoteContent: remote,
        store: store,
        lastSyncExportedAt: null,
      );
      expect(d, SyncDirection.download);
    });
  });

  group('上传 / 恢复闭环', () {
    test('上传后另一设备下载恢复，数据一致', () async {
      final (storeA, prefsA) = await _fresh();
      final backend = FakeBackend();
      await SyncService.uploadBackup(storeA, backend, prefsA);

      // 另一台设备（无数据）
      final (storeB, prefsB) = await _fresh();
      storeB.clearAll();
      final outcome = await SyncService.downloadBackup(storeB, backend, prefsB);
      expect(outcome.ok, isTrue);
      expect(storeB.items.length, storeA.items.length);
      expect(storeB.items.first.name, storeA.items.first.name);
    });

    test('云端备份损坏 → 恢复失败', () async {
      final (store, prefs) = await _fresh();
      final backend = FakeBackend('这不是 JSON');
      final outcome = await SyncService.downloadBackup(store, backend, prefs);
      expect(outcome.ok, isFalse);
      expect(outcome.message, contains('无法解析'));
    });

    test('后端异常 → 返回失败结果而非抛出', () async {
      final (store, prefs) = await _fresh();
      final backend = FakeBackend()..shouldThrow = true;
      final outcome = await SyncService.uploadBackup(store, backend, prefs);
      expect(outcome.ok, isFalse);
      expect(outcome.message, contains('无法连接'));
    });
  });

  group('冲突判定', () {
    test('双边都有变更 → conflict（交由用户决定）', () async {
      final (storeA, prefsA) = await _fresh();
      final backend = FakeBackend();
      await SyncService.uploadBackup(storeA, backend, prefsA);

      // 设备 B：有本地新变更，且从未同步过
      final (storeB, prefsB) = await _fresh();
      storeB.patchItem(storeB.items.first.id, (item) => item.note = 'B 端修改');
      final decision = await SyncService.smartSync(storeB, backend, prefsB);
      expect(decision.kind, 'conflict');
      expect(decision.remoteAt, isNotNull);
    });

    test('智能同步：云端为空 → 自动上传', () async {
      final (store, prefs) = await _fresh();
      final backend = FakeBackend();
      final decision = await SyncService.smartSync(store, backend, prefs);
      expect(decision.kind, 'done');
      expect(backend.remote, isNotNull);
    });

    test('智能同步：一致 → none', () async {
      final (store, prefs) = await _fresh();
      final backend = FakeBackend();
      await SyncService.uploadBackup(store, backend, prefs);
      final decision = await SyncService.smartSync(store, backend, prefs);
      expect(decision.kind, 'none');
    });
  });
}
