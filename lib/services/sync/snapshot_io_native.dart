/// 快照存储 native 实现：应用文档目录下的 snapshots/ 文件夹（支持大内容）
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 快照保留份数上限（native 端文件存储，可多留）
const int snapshotCapacity = 30;

/// 快照读写抽象（snapshot_store 使用；测试可用内存实现）
abstract class SnapshotStorage {
  Future<String?> read(String id);
  Future<void> write(String id, String content);
  Future<void> delete(String id);
}

SnapshotStorage getSnapshotStorage() => _FileSnapshotStorage();

class _FileSnapshotStorage implements SnapshotStorage {
  Directory? _cache;

  Future<Directory> _dir() async {
    final cached = _cache;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}snapshots');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cache = dir;
    return dir;
  }

  @override
  Future<String?> read(String id) async {
    try {
      final file = File('${(await _dir()).path}${Platform.pathSeparator}$id.json');
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String id, String content) async {
    final file = File('${(await _dir()).path}${Platform.pathSeparator}$id.json');
    await file.writeAsString(content, flush: true);
  }

  @override
  Future<void> delete(String id) async {
    try {
      final file = File('${(await _dir()).path}${Platform.pathSeparator}$id.json');
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // 忽略删除失败
    }
  }
}
