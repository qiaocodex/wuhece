/// 云同步区：服务商选择（WebDAV / Supabase / S3 / BoxBook Cloud）、
/// 各自字段配置、测试连接、上传 / 恢复 / 智能同步
/// （settings_page.dart 的 part，属于同一 library）
part of 'settings_page.dart';

/// 各服务商的字段定义：(key, label, defaultValue, obscure, hint)
class _FieldDef {
  const _FieldDef(
    this.key,
    this.label, {
    this.defaultValue = '',
    this.obscure = false,
    this.hint = '',
  });

  final String key;
  final String label;
  final String defaultValue;
  final bool obscure;
  final String hint;
}

const Map<String, List<_FieldDef>> _kProviderFields = {
  'webdav': [
    _FieldDef('url', '服务器地址', hint: 'https://dav.jianguoyun.com/dav/'),
    _FieldDef('user', '账号'),
    _FieldDef('password', '密码（坚果云为应用密码）', obscure: true),
    _FieldDef('remotePath', '远端路径', defaultValue: '/wuhece/backup.json'),
  ],
  'supabase': [
    _FieldDef('url', 'Project URL', hint: 'https://xxxx.supabase.co'),
    _FieldDef('anonKey', 'Anon Key', obscure: true),
    _FieldDef('table', '表名', defaultValue: 'wuhece_backups'),
  ],
  's3': [
    _FieldDef('endpoint', 'Endpoint', hint: 'https://s3.amazonaws.com 或 R2 / MinIO 地址'),
    _FieldDef('region', 'Region', defaultValue: 'auto'),
    _FieldDef('accessKey', 'Access Key'),
    _FieldDef('secretKey', 'Secret Key', obscure: true),
    _FieldDef('bucket', '存储桶'),
    _FieldDef('objectPath', '对象路径', defaultValue: 'wuhece/backup.json'),
  ],
  'boxbook': [
    _FieldDef('url', '服务器地址', hint: 'http://192.168.1.10:8800'),
    _FieldDef('user', '用户名'),
    _FieldDef('password', '密码', obscure: true),
  ],
};

const Map<String, String> _kProviderLabels = {
  'webdav': 'WebDAV',
  'supabase': 'Supabase',
  's3': 'S3 协议',
  'boxbook': 'BoxBook Cloud',
};

const Map<String, String> _kProviderSub = {
  'webdav': '坚果云 / 群晖 / 绿联 / Nextcloud（标准 WebDAV 协议）',
  'supabase': '开源后端 · 免费额度充足 · 无 NAS 的跨平台方案',
  's3': 'AWS S3 / Cloudflare R2 / MinIO · 免费额度大 · 灵活配置',
  'boxbook': '自托管服务端 · 多用户与共享物品册 · Docker 一键部署',
};

class _SyncSection extends StatefulWidget {
  const _SyncSection();

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  late SyncSettings _settings;
  final Map<String, TextEditingController> _ctrls = {};
  List<BoxBookBook> _boxBooks = [];
  String _busy = '';
  String _lastSyncAt = '';

  AppStore get store => AppStore.instance;

  @override
  void initState() {
    super.initState();
    _settings = SyncSettings.load(store.prefs);
    _lastSyncAt = SyncService.lastSyncAt(store.prefs) ?? '';
    for (final def in _kProviderFields[_settings.provider] ?? const <_FieldDef>[]) {
      _ctrl(_settings.provider, def);
    }
    if (_settings.provider == 'boxbook' &&
        (_settings.fields['boxbook']?['token'] ?? '').isNotEmpty) {
      _refreshBoxBooks();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String provider, _FieldDef def) {
    final key = '$provider.${def.key}';
    return _ctrls.putIfAbsent(
      key,
      () => TextEditingController(
        text: _settings.fields[provider]?[def.key] ?? def.defaultValue,
      ),
    );
  }

  void _switchProvider(String provider) {
    if (provider == _settings.provider) return;
    if (provider == 'icloud') {
      toast(context, 'iCloud 同步需要 iOS 原生能力，即将支持');
      return;
    }
    setState(() {
      _settings.provider = provider;
      for (final def in _kProviderFields[provider] ?? const <_FieldDef>[]) {
        _ctrl(provider, def);
      }
    });
    SyncSettings.save(store.prefs, _settings);
  }

  /// 读取当前服务商的全部字段并持久化
  Map<String, String> _collectFields() {
    final defs = _kProviderFields[_settings.provider] ?? const <_FieldDef>[];
    final values = <String, String>{};
    for (final def in defs) {
      values[def.key] = _ctrl(_settings.provider, def).text.trim();
    }
    _settings.fields[_settings.provider] = values;
    return values;
  }

  Future<bool> _persist() async {
    _collectFields();
    final configured = _settings.fields[_settings.provider] ?? const {};
    final requiredKeys = {
      'webdav': ['url', 'user', 'password'],
      'supabase': ['url', 'anonKey'],
      's3': ['endpoint', 'accessKey', 'secretKey', 'bucket'],
      'boxbook': ['url', 'user', 'password'],
    }[_settings.provider] ?? const [];
    for (final key in requiredKeys) {
      if ((configured[key] ?? '').trim().isEmpty) {
        final def = (_kProviderFields[_settings.provider] ?? const <_FieldDef>[])
            .firstWhere((d) => d.key == key, orElse: () => _FieldDef(key, key));
        if (mounted) toast(context, '请先填写「${def.label}」', error: true);
        return false;
      }
    }
    await SyncSettings.save(store.prefs, _settings);
    return true;
  }

  Future<SyncBackend?> _backend() async {
    if (!await _persist()) return null;
    if (_settings.provider == 'boxbook') {
      if (!mounted) return null;
      if ((_settings.fields['boxbook']?['token'] ?? '').isEmpty) {
        toast(context, '请先登录 BoxBook 服务端并选择物品册', error: true);
        return null;
      }
      if (_settings.bookId.isEmpty) {
        toast(context, '请先选择要同步的物品册', error: true);
        return null;
      }
    }
    return buildBackend(_settings);
  }

  Future<void> _run(String action, Future<void> Function() task) async {
    setState(() => _busy = action);
    await task();
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _test() async {
    final backend = await _backend();
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
    final backend = await _backend();
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
    final backend = await _backend();
    if (backend == null || !mounted) return;
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
    final backend = await _backend();
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

  /* ------------------------- BoxBook 登录与物品册 ------------------------- */

  Future<void> _boxLogin() async {
    final values = _collectFields();
    await _run('login', () async {
      try {
        final token = await BoxBookBackend.login(
          serverUrl: values['url'] ?? '',
          username: values['user'] ?? '',
          password: values['password'] ?? '',
        );
        _settings.fields['boxbook'] = {...values, 'token': token};
        await SyncSettings.save(store.prefs, _settings);
        await _refreshBoxBooks();
        if (mounted) toast(context, '登录成功，请选择要同步的物品册');
      } on SyncException catch (err) {
        if (mounted) toast(context, err.message, error: true);
      }
    });
  }

  Future<void> _refreshBoxBooks() async {
    final token = _settings.fields['boxbook']?['token'] ?? '';
    final url = _settings.fields['boxbook']?['url'] ?? '';
    if (token.isEmpty || url.isEmpty) return;
    final books = await BoxBookBackend.listBooks(serverUrl: url, token: token);
    if (mounted) setState(() => _boxBooks = books);
  }

  Future<void> _createBoxBook() async {
    final nameCtrl = TextEditingController();
    final name = await showResponsive<String>(
      context,
      maxWidth: 420,
      builder: (_) => FormScaffold(
        title: '新建物品册',
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
        body: FormField2(
          label: '物品册名称',
          child: TextField(
            controller: nameCtrl,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(hintText: '例如：家庭物品册', counterText: ''),
          ),
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final token = _settings.fields['boxbook']?['token'] ?? '';
    final url = _settings.fields['boxbook']?['url'] ?? '';
    await _run('createBook', () async {
      try {
        final book = await BoxBookBackend.createBook(serverUrl: url, token: token, name: name);
        await _refreshBoxBooks();
        setState(() {
          _settings.bookId = book.id.toString();
          _settings.bookName = book.name;
        });
        await SyncSettings.save(store.prefs, _settings);
        if (mounted) toast(context, '物品册「${book.name}」已创建并选中');
      } on SyncException catch (err) {
        if (mounted) toast(context, err.message, error: true);
      }
    });
  }

  void _refreshLastSync() {
    setState(() => _lastSyncAt = SyncService.lastSyncAt(store.prefs) ?? '');
  }

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

  @override
  Widget build(BuildContext context) {
    final provider = _settings.provider;
    final defs = _kProviderFields[provider] ?? const <_FieldDef>[];
    final isBox = provider == 'boxbook';

    return SectionCard(
      title: '云同步',
      sub: '多设备数据同步 · 数据存放在你自己的网盘或服务器',
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
            label: '同步服务商',
            child: SelectField<String>(
              value: provider,
              items: [
                for (final p in ['webdav', 'supabase', 's3', 'boxbook'])
                  DropdownMenuItem(value: p, child: Text(_kProviderLabels[p] ?? p)),
              ],
              onChanged: (v) => _switchProvider(v ?? provider),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _kProviderSub[provider] ?? '',
            style: TextStyle(fontSize: 11, color: context.gc.muted2),
          ),
          const SizedBox(height: 12),
          for (final def in defs) ...[
            FormField2(
              label: def.label,
              child: TextField(
                controller: _ctrl(provider, def),
                obscureText: def.obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(hintText: def.hint.isEmpty ? null : def.hint),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isBox) ..._boxBookExtras(),
          const SizedBox(height: 6),
          row([
            actionButton('test', '测试连接', Icons.wifi_tethering_outlined, _test),
            actionButton('smart', '立即同步', Icons.sync, _smartSync, filled: true),
          ]),
          const SizedBox(height: 10),
          row([
            actionButton('upload', '上传备份到云端', Icons.upload_outlined, _upload),
            actionButton('download', '从云端恢复', Icons.download_outlined, _download),
          ]),
          if (provider == 'supabase') ...[
            const SizedBox(height: 10),
            Text(
              '首次使用：在 Supabase 项目 SQL Editor 执行以下建表 SQL ——\n'
              '${SupabaseBackend.setupSql}',
              style: TextStyle(fontSize: 11, color: context.gc.muted2, height: 1.6),
            ),
          ],
          if (isBox) ...[
            const SizedBox(height: 10),
            Text(
              '自托管服务端部署与说明见仓库 server/ 目录（Docker 一键部署，支持多用户与共享物品册）。',
              style: TextStyle(fontSize: 11, color: context.gc.muted2),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _boxBookExtras() {
    final booksLoaded = _boxBooks.isNotEmpty;
    final bookOptions = _boxBooks
        .map(
          (b) => DropdownMenuItem(
            value: b.id.toString(),
            child: Text('${b.name}（${b.ownerName} · ${_roleLabel(b.role)}）'),
          ),
        )
        .toList();
    return [
      const SizedBox(height: 6),
      row([
        actionButton('login', '登录并获取物品册', Icons.login, _boxLogin, filled: true),
        actionButton(
          'createBook',
          '新建物品册',
          Icons.add,
          (_settings.fields['boxbook']?['token'] ?? '').isNotEmpty ? () => _createBoxBook() : null,
        ),
      ]),
      if (booksLoaded) ...[
        const SizedBox(height: 12),
        FormField2(
          label: '要同步的物品册',
          child: SelectField<String>(
            value: _settings.bookId,
            items: bookOptions,
            onChanged: (v) {
              setState(() {
                _settings.bookId = v ?? '';
                _settings.bookName =
                    _boxBooks.where((b) => b.id.toString() == v).firstOrNull?.name ?? '';
              });
              SyncSettings.save(store.prefs, _settings);
            },
          ),
        ),
      ],
    ];
  }

  String _roleLabel(String role) => switch (role) {
        'owner' => '创建者',
        'editor' => '可编辑',
        _ => '只读',
      };
}
