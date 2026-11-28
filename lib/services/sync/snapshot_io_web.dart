/// 快照存储 Web 实现：localStorage（容量有限，份数收紧到 3 份）
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 快照保留份数上限（localStorage 容量有限，收紧）
const int snapshotCapacity = 3;

/// 快照读写抽象（snapshot_store 使用）
abstract class SnapshotStorage {
  Future<String?> read(String id);
  Future<void> write(String id, String content);
  Future<void> delete(String id);
}

SnapshotStorage getSnapshotStorage() => _PrefsSnapshotStorage();

class _PrefsSnapshotStorage implements SnapshotStorage {
  static const _prefix = 'guiwu.snapshot.';

  @override
  Future<String?> read(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$id');
  }

  @override
  Future<void> write(String id, String content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$id', content);
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
  }
}
