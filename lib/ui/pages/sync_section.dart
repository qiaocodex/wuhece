/// 云同步区：WebDAV 配置、测试连接、上传 / 恢复 / 智能同步
/// （settings_page.dart 的 part，属于同一 library）
part of 'settings_page.dart';

class _SyncSection extends StatefulWidget {
  const _SyncSection();

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _pathCtrl;
  String _busy = ''; // 正在执行的动作标识
  String _lastSyncAt = '';

  AppStore get store => AppStore.instance;

  @override
  void initState() {
    super.initState();
    final config = SyncService.loadConfig(store.prefs);
    _urlCtrl = TextEditingController(text: config?.url ?? '');
    _userCtrl = TextEditingController(text: config?.user ?? '');
    _pwdCtrl = TextEditingController(text: config?.password ?? '');
    _pathCtrl = TextEditingController(
      text: config?.remotePath ?? '/wuhece/backup.json',
    );
    _lastSyncAt = SyncService.lastSyncAt(store.prefs) ?? '';
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  SyncConfig _readConfig() => SyncConfig(
        url: _urlCtrl.text.trim(),
        user: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        remotePath:
            _pathCtrl.text.trim().isEmpty ? '/wuhece/backup.json' : _pathCtrl.text.trim(),
      );

  WebDavBackend? _backend() {
    final config = _readConfig();
    if (!config.isConfigured) {
      toast(context, '请先填写服务器地址、账号与密码', error: true);
      return null;
    }
    return WebDavBackend(config);
  }

  Future<void> _run(String action, Future<void> Function() task) async {
    setState(() => _busy = action);
    await task();
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _test() async {
    final backend = _backend();
    if (backend == null) return;
    await _run('test', () async {
      try {
        await backend.testConnection();
        if (mounted) toast(context, '连接成功');
      } on SyncException catch (err) {
        if (mounted) toast(context, err.message, error: true);
      }
    });
  }

  Future<void> _upload() async {
    final backend = _backend();
    if (backend == null) return;
    await _run('upload', () async {
      final outcome = await SyncService.uploadBackup(store, backend, store.prefs);
      if (mounted) {
        toast(context, outcome.message, error: !outcome.ok);
        if (outcome.ok) _refreshLastSync();
      }
    });
  }

  Future<void> _download() async {
    final backend = _backend();
    if (backend == null) return;
    final ok = await confirmDialog(
      context,
      title: '从云端恢复',
      message: '将用云端备份覆盖本机的全部数据，本机新增内容会丢失。确定继续吗？',
      confirmText: '覆盖恢复',
      danger: true,
    );
    if (!ok) return;
    await _run('download', () async {
      final outcome = await SyncService.downloadBackup(store, backend, store.prefs);
      if (mounted) {
        toast(context, outcome.message, error: !outcome.ok);
        if (outcome.ok) _refreshLastSync();
      }
    });
  }

  Future<void> _smartSync() async {
    final backend = _backend();
    if (backend == null) return;
    await _run('smart', () async {
      SyncDecision decision;
      try {
        decision = await SyncService.smartSync(store, backend, store.prefs);
      } on SyncException catch (err) {
        if (mounted) toast(context, err.message, error: true);
        return;
      }
      if (!mounted) return;
      switch (decision.kind) {
        case 'none':
          toast(context, '本地与云端数据一致，无需同步');
        case 'done':
          toast(context, decision.outcome.message, error: !decision.outcome.ok);
          if (decision.outcome.ok) _refreshLastSync();
        case 'conflict':
          final keepLocal = await _askConflict(decision.remoteAt);
          if (keepLocal == null || !mounted) return;
          final outcome = keepLocal
              ? await SyncService.uploadBackup(store, backend, store.prefs)
              : await SyncService.downloadBackup(store, backend, store.prefs);
          if (mounted) {
            toast(context, outcome.message, error: !outcome.ok);
            if (outcome.ok) _refreshLastSync();
          }
      }
    });
  }

  /// 双边都有变更时询问保留哪边；null = 取消
  Future<bool?> _askConflict(String? remoteAt) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '本地与云端都有变更',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '云端备份时间：${remoteAt ?? '未知'}\n保留哪一份数据？',
          style: const TextStyle(fontSize: 13, color: GColors.inkSoft, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('下载云端', style: TextStyle(color: GColors.blue)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('上传本地'),
          ),
        ],
      ),
    );
  }

  void _refreshLastSync() {
    setState(() => _lastSyncAt = SyncService.lastSyncAt(store.prefs) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    Widget actionButton(
      String actionKey,
      String label,
      IconData icon,
      VoidCallback? onPressed, {
      bool filled = false,
    }) {
      final busy = _busy == actionKey;
      if (filled) {
        return FilledButton.icon(
          onPressed: busy || onPressed == null ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 14),
          label: Text(label),
        );
      }
      return OutlinedButton.icon(
        onPressed: busy || onPressed == null ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 14),
        label: Text(label),
      );
    }

    Widget row(List<Widget> children) {
      final rowChildren = <Widget>[];
      for (final c in children) {
        rowChildren.add(Expanded(child: c));
        rowChildren.add(const SizedBox(width: 10));
      }
      rowChildren.removeLast();
      return Row(children: rowChildren);
    }

    return SectionCard(
      title: '云同步',
      sub: '多设备数据同步（WebDAV：坚果云 / 群晖 / 绿联 / Nextcloud）',
      action: _lastSyncAt.isEmpty
          ? MiniBadge(label: '未同步', color: context.gc.muted, bg: context.gc.bgDeep)
          : MiniBadge(
              label: '同步于 ${formatDate(_lastSyncAt)}',
              color: context.gc.primary,
              bg: context.gc.primaryWeak,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormField2(
            label: '服务器地址',
            child: TextField(
              controller: _urlCtrl,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'https://dav.jianguoyun.com/dav/'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FormField2(
                  label: '账号',
                  child: TextField(
                    controller: _userCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FormField2(
                  label: '密码（坚果云为应用密码）',
                  child: TextField(
                    controller: _pwdCtrl,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FormField2(
            label: '远端路径',
            child: TextField(
              controller: _pathCtrl,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
          const SizedBox(height: 14),
          row([
            actionButton('test', '测试连接', Icons.wifi_tethering_outlined, _test),
            actionButton('smart', '立即同步', Icons.sync, _smartSync, filled: true),
          ]),
          const SizedBox(height: 10),
          row([
            actionButton('upload', '上传备份到云端', Icons.upload_outlined, _upload),
            actionButton('download', '从云端恢复', Icons.download_outlined, _download),
          ]),
          const SizedBox(height: 10),
          const Text(
            '数据以 JSON 备份形式存放在你自己的网盘，应用不经手第三方服务。'
            '坚果云：网页端登录 → 安全选项 → 添加应用密码；'
            '群晖 / Nextcloud 填对应 WebDAV 地址即可。',
            style: TextStyle(fontSize: 11, color: GColors.muted2, height: 1.6),
          ),
        ],
      ),
    );
  }
}
