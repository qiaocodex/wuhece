/// 同步记录页：按时间倒序展示每次同步 / 上传 / 恢复 / 测试的结果
library;

import 'package:material_ui/material_ui.dart';

import '../../services/dates.dart';
import '../../services/sync/sync_backend.dart';
import '../../services/sync/sync_log.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 打开同步记录页
Future<void> openSyncLogPage(BuildContext context) {
  return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncLogPage()));
}

class SyncLogPage extends StatelessWidget {
  const SyncLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = SyncLog.load(AppStore.instance.prefs);
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
        title: Text('同步记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: [
          MiniBadge(
            label: '${logs.length} 条',
            color: context.gc.muted,
            bg: context.gc.bgDeep,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: logs.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: '还没有同步记录',
              desc: '每次智能同步、上传、恢复或测试连接都会在这里留痕。',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final log = logs[i];
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: context.gc.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.gc.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        log.ok ? Icons.check_circle : Icons.error_outline,
                        size: 17,
                        color: log.ok ? context.gc.primary : context.gc.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  SyncLog.actionLabel(log.action),
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.gc.ink),
                                ),
                                const SizedBox(width: 8),
                                MiniBadge(
                                  label: syncProviderLabel(log.provider),
                                  color: context.gc.muted,
                                  bg: context.gc.bgDeep,
                                ),
                                const Spacer(),
                                Text(
                                  formatDateTime(log.at),
                                  style: TextStyle(fontSize: 11.5, color: context.gc.muted2),
                                ),
                              ],
                            ),
                            if (log.message.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                log.message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: log.ok ? context.gc.muted : context.gc.danger,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
