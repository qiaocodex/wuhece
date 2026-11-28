/// 同步记录与本地快照测试（内存存储介质）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/sync/snapshot_store.dart';
import 'package:guiwu/services/sync/sync_log.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存快照介质（替代文件/localStorage）
class MemorySnapshotStorage implements SnapshotStorage {
  final Map<String, String> files = {};

  @override
  Future<String?> read(String id) async => files[id];

  @override
  Future<void> write(String id, String content) async => files[id] = content;

  @override
  Future<void> delete(String id) async => files.remove(id);
}

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return store;
}

void main() {
  group('SyncLog 同步记录', () {
    test('记录追加、最新在前、上限裁剪', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await SyncLog.add(prefs, const SyncLogEntry(
        at: '2026-11-28T09:00:00', action: 'smart', provider: 'baidu', ok: true, message: '已上传',
      ));
      await SyncLog.add(prefs, const SyncLogEntry(
        at: '2026-11-28T09:05:00', action: 'test', provider: 'webdav', ok: false, message: '连接失败',
      ));
      final logs = SyncLog.load(prefs);
      expect(logs.length, 2);
      expect(logs.first.action, 'test'); // 最新在前
      expect(SyncLog.actionLabel('smart'), '智能同步');
      expect(SyncLog.actionLabel('restore'), '快照恢复');

      for (var i = 0; i < 120; i++) {
        await SyncLog.add(prefs, SyncLogEntry(
          at: 't$i', action: 'upload', provider: 'baidu', ok: true, message: 'm$i',
        ));
      }
      expect(SyncLog.load(prefs).length, 100);
    });

    test('空/损坏数据返回空列表', () async {
      SharedPreferences.setMockInitialValues({'guiwu.sync.log': 'not-json'});
      final prefs = await SharedPreferences.getInstance();
      expect(SyncLog.load(prefs), isEmpty);
    });
  });

  group('SnapshotStore 本地快照', () {
    test('保存 / 列表 / 恢复闭环', () async {
      final store = await _freshStore();
      final storage = MemorySnapshotStorage();
      store.addItem(name: '测试物品', categoryId: store.categories.first.id, purchaseDate: '2026-11-28');
      final afterAdd = store.items.length; // 种子数据 + 1

      final id = await SnapshotStore.save(store, storageOverride: storage);
      final list0 = SnapshotStore.list(store.prefs);
      expect(list0.length, 1);
      expect(list0.first.id, id);
      expect(list0.first.itemCount, afterAdd);
      expect(storage.files[id], contains('测试物品'));

      // 数据变更后恢复快照
      store.addItem(name: '后来新增', categoryId: store.categories.first.id, purchaseDate: '2026-11-28');
      expect(store.items.length, afterAdd + 1);
      final ok = await SnapshotStore.restore(store, store.prefs, id, storageOverride: storage);
      expect(ok, isTrue);
      expect(store.items.length, afterAdd);
      expect(store.items.any((it) => it.name == '测试物品'), isTrue);
      expect(store.items.any((it) => it.name == '后来新增'), isFalse);
    });

    test('恢复不存在的快照返回 false', () async {
      final store = await _freshStore();
      expect(
        await SnapshotStore.restore(store, store.prefs, 'snap-none', storageOverride: MemorySnapshotStorage()),
        isFalse,
      );
    });

    test('删除快照同时清理索引与内容', () async {
      final store = await _freshStore();
      final storage = MemorySnapshotStorage();
      final id = await SnapshotStore.save(store, storageOverride: storage);
      await SnapshotStore.delete(store.prefs, id, storageOverride: storage);
      expect(SnapshotStore.list(store.prefs), isEmpty);
      expect(storage.files[id], isNull);
    });
  });
}
