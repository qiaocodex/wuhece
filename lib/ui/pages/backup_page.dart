/// 网盘 & 备份中心：网盘同步 / 备份数据 / 历史版本备份 三入口
/// （对应参考记账类 App 的「网盘&备份」独立设置项）
library;

import 'package:material_ui/material_ui.dart';

import '../../services/dates.dart';
import '../../services/sync/snapshot_store.dart';
import '../../services/sync/sync_backend.dart';
import '../../services/sync/sync_service.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'backup_data_page.dart';
import 'snapshot_page.dart';
import 'sync_page.dart';

/// 打开网盘 & 备份中心
Future<void> openBackupPage(BuildContext context) {
  return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BackupPage()));
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  AppStore get store => AppStore.instance;

  /// 二级页返回后刷新状态徽章
  Future<void> _go(Future<void> Function(BuildContext) opener) async {
    await opener(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final prefs = store.prefs;
    final settings = SyncSettings.load(prefs);
    final lastSyncAt = SyncService.lastSyncAt(prefs) ?? '';
    final configured = isProviderConfigured(settings) &&
        (settings.provider != 'baidu' || (settings.fields['baidu']?['accessToken'] ?? '').isNotEmpty) &&
        (settings.provider != 'boxbook' || (settings.fields['boxbook']?['token'] ?? '').isNotEmpty);
    final snapshotCount = SnapshotStore.list(prefs).length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.gc.bg,
        surfaceTintColor: context.gc.bg,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('网盘 & 备份', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: const [SizedBox(width: 8)],
      ),
      body: pageContainer(
        context,
        children: [
          PageHeader(
            title: '网盘 & 备份',
            sub: configured
                ? '当前通过 ${syncProviderLabel(settings.provider)} 同步${lastSyncAt.isEmpty ? '' : ' · 同步于 ${formatDate(lastSyncAt)}'}'
                : '尚未配置同步 · 数据目前仅保存在本机',
          ),
          AppCard(
            child: Column(
              children: [
                _EntryTile(
                  icon: Icons.cloud_sync_outlined,
                  title: '网盘同步',
                  desc: configured
                      ? '${syncProviderLabel(settings.provider)} · 多设备数据同步'
                      : '支持 百度网盘 / WebDAV / Supabase / S3 / BoxBook',
                  onTap: () => _go(openSyncPage),
                ),
                const Divider(height: 1),
                _EntryTile(
                  icon: Icons.backup_outlined,
                  title: '备份数据',
                  desc: '导出完整备份（JSON），或从备份文件恢复',
                  onTap: () => _go(openBackupDataPage),
                ),
                const Divider(height: 1),
                _EntryTile(
                  icon: Icons.history_rounded,
                  title: '历史版本备份',
                  desc: snapshotCount == 0
                      ? '同步或恢复前的数据自动留存为快照，可随时回滚'
                      : '已留存 $snapshotCount 份本地快照，可随时恢复到任意时点',
                  onTap: () => _go(openSnapshotPage),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '数据始终保存在本机；同步只是把你自己的备份放到你选择的网盘/服务器。'
            '每次云端上传或恢复前都会自动拍一份本地快照，误覆盖也能找回。',
            style: TextStyle(fontSize: 11.5, color: context.gc.muted2, height: 1.7),
          ),
        ],
      ),
    );
  }
}

/// 入口行（图标 + 标题描述 + chevron）
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.icon, required this.title, required this.desc, required this.onTap});

  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.gc.primaryWeak,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: context.gc.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.gc.ink)),
                  const SizedBox(height: 3),
                  Text(desc, style: TextStyle(fontSize: 12, color: context.gc.muted, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: context.gc.muted),
          ],
        ),
      ),
    );
  }
}
