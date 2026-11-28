/// 备份数据页：导出完整备份（JSON）/ 从备份文件恢复（JSON）
/// （自设置页「数据管理」迁出，与 Web 版备份格式互通）
library;

import 'package:material_ui/material_ui.dart';

import '../../services/dates.dart';
import '../../services/file_io.dart' as file_io;
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 打开备份数据页
Future<void> openBackupDataPage(BuildContext context) {
  return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BackupDataPage()));
}

class BackupDataPage extends StatelessWidget {
  const BackupDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final canPick = file_io.filePickSupported;

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
        title: Text('备份数据', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: const [SizedBox(width: 8)],
      ),
      body: pageContainer(
        context,
        children: [
          PageHeader(
            title: '备份数据',
            sub: '备份文件与 Web 版互通 · 包含物品、空间、分类与使用记录',
          ),
          SectionCard(
            title: '导出备份',
            sub: '生成 JSON 备份文件（手机端走系统分享，桌面端弹保存对话框）',
            child: SettingRow(
              title: '导出完整备份',
              desc: '包含 ${store.items.length} 件物品与全部设置，恢复时整体覆盖',
              action: FilledButton.icon(
                onPressed: () => _exportJson(context),
                icon: const Icon(Icons.download_outlined, size: 14),
                label: const Text('导出 JSON'),
              ),
            ),
          ),
          const SizedBox(height: kSectionGap),
          SectionCard(
            title: '导入备份',
            sub: canPick
                ? '从 JSON 备份恢复，会覆盖当前全部数据（恢复前建议先导出一份）'
                : '手机端暂不支持文件导入，请使用 Web 或桌面端操作',
            child: SettingRow(
              title: '从备份文件恢复',
              desc: '选择 guiwu-backup-*.json 或 Web 版导出的备份',
              action: OutlinedButton.icon(
                onPressed: canPick ? () => _importJson(context) : null,
                icon: const Icon(Icons.upload_outlined, size: 14),
                label: const Text('选择文件'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportJson(BuildContext context) async {
    final store = AppStore.instance;
    final ok = await file_io.exportTextFile(
      fileName: 'guiwu-backup-${toISODate()}.json',
      content: store.exportJson(),
      mime: 'application/json',
    );
    if (ok && context.mounted) toast(context, '备份已导出');
  }

  Future<void> _importJson(BuildContext context) async {
    final content = await file_io.pickTextFileContent(
      label: 'JSON 备份',
      extensions: ['json'],
      mime: 'application/json',
    );
    if (content == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: '导入备份',
      message: '导入会覆盖当前全部数据，建议先导出一次备份。确定继续吗？',
      confirmText: '继续导入',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      AppStore.instance.importJson(content);
      toast(context, '数据已导入');
    } catch (err) {
      toast(context, err is FormatException ? err.message : '导入失败，文件格式不正确', error: true);
    }
  }
}
