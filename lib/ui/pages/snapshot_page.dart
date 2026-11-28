/// 历史版本备份页：本地快照列表，支持恢复 / 删除 / 手动拍快照
library;

import 'package:material_ui/material_ui.dart';

import '../../services/dates.dart';
import '../../services/format.dart';
import '../../services/sync/snapshot_store.dart';
import '../../services/sync/sync_log.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 打开历史版本备份页
Future<void> openSnapshotPage(BuildContext context) {
  return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SnapshotPage()));
}

class SnapshotPage extends StatefulWidget {
  const SnapshotPage({super.key});

  @override
  State<SnapshotPage> createState() => _SnapshotPageState();
}

class _SnapshotPageState extends State<SnapshotPage> {
  bool _busy = false;

  AppStore get store => AppStore.instance;

  void _reload() => setState(() {});

  Future<void> _takeSnapshot() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SnapshotStore.save(store);
      if (mounted) toast(context, '已保存当前数据快照');
    } catch (err) {
      if (mounted) toast(context, '快照保存失败：$err', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _restore(SnapshotIndexEntry entry) async {
    final ok = await confirmDialog(
      context,
      title: '恢复快照',
      message: '将把数据回滚到 ${formatDateTime(entry.at)} 的状态'
          '（${entry.itemCount} 件物品），当前数据会先自动拍一份快照。确定继续吗？',
      confirmText: '恢复',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      // 恢复前先把当前状态拍快照，防误回滚
      await SnapshotStore.save(store);
      final done = await SnapshotStore.restore(store, store.prefs, entry.id);
      if (mounted) {
        toast(context, done ? '已恢复到 ${formatDateTime(entry.at)} 的数据' : '快照内容缺失，无法恢复', error: !done);
      }
      if (done) {
        await SyncLog.add(store.prefs, SyncLogEntry(
          at: DateTime.now().toIso8601String(),
          action: 'restore',
          provider: 'local',
          ok: true,
          message: '已恢复本地快照（${entry.itemCount} 件物品）',
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _delete(SnapshotIndexEntry entry) async {
    final ok = await confirmDialog(
      context,
      title: '删除快照',
      message: '删除 ${formatDateTime(entry.at)} 的快照？该操作不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await SnapshotStore.delete(store.prefs, entry.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gc.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.gc.bg,
        surfaceTintColor: context.gc.bg,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('历史版本备份', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: [
          IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_a_photo_outlined, size: 19),
            tooltip: '拍快照（保存当前数据）',
            onPressed: _takeSnapshot,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list0 = SnapshotStore.list(store.prefs);
          return pageContainer(
            context,
            children: [
              PageHeader(
                title: '历史版本备份',
                sub: '共 ${list0.length} 份快照 · 云端上传或恢复前会自动留存',
              ),
              if (list0.isEmpty)
                EmptyState(
                  icon: Icons.history_rounded,
                  title: '还没有快照',
                  desc: '配置网盘同步后，每次云端上传或恢复前会自动拍快照；'
                      '也可以点右上角按钮手动保存当前数据。',
                  action: FilledButton.icon(
                    onPressed: _takeSnapshot,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 14),
                    label: const Text('保存当前数据为快照'),
                  ),
                )
              else
                AppCard(
                  child: Column(
                    children: [
                      for (final entry in list0) ...[
                        _snapshotRow(entry),
                        if (entry != list0.last) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _snapshotRow(SnapshotIndexEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 17,
            color: context.gc.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime(entry.at),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.gc.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.itemCount} 件物品 · ${bytesText(entry.bytes)}',
                  style: TextStyle(fontSize: 12, color: context.gc.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              onPressed: _busy ? null : () => _restore(entry),
              icon: const Icon(Icons.restore, size: 15),
              tooltip: '恢复到此版本',
              color: context.gc.primary,
              padding: EdgeInsets.zero,
            ),
          ),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              onPressed: _busy ? null : () => _delete(entry),
              icon: const Icon(Icons.delete_outline, size: 15),
              tooltip: '删除快照',
              color: context.gc.danger,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
