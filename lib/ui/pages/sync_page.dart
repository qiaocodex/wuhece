/// 网盘同步页：服务商选择（百度网盘 / WebDAV / Supabase / S3 / BoxBook Cloud）、
/// 百度设备码授权、启动自动同步开关、同步记录入口、测试 / 同步 / 上传 / 恢复
/// （自 settings_page 的云同步 Section 迁移为独立页面）
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/dates.dart';
import '../../services/sync/sync_backend.dart';
import '../../services/sync/sync_log.dart';
import '../../services/sync/sync_service.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'sync_log_page.dart';

/// 打开网盘同步页
Future<void> openSyncPage(BuildContext context) {
  return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncPage()));
}

/// 各服务商的字段定义：(key, label, defaultValue, obscure, hint)
class SyncFieldDef {
  const SyncFieldDef(
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

const Map<String, List<SyncFieldDef>> kProviderFields = {
  'baidu': [
    SyncFieldDef('appKey', 'AppKey', hint: 'pan.baidu.com/union 创建应用后获取'),
    SyncFieldDef('secretKey', 'SecretKey', obscure: true),
    SyncFieldDef('remoteDir', '远程目录', defaultValue: '/apps/物盒册', hint: '与创建应用时填写的应用名一致'),
  ],
  'webdav': [
    SyncFieldDef('url', '服务器地址', hint: 'https://dav.jianguoyun.com/dav/'),
    SyncFieldDef('user', '账号'),
    SyncFieldDef('password', '密码（坚果云为应用密码）', obscure: true),
    SyncFieldDef('remotePath', '远端路径', defaultValue: '/wuhece/backup.json'),
  ],
  'supabase': [
    SyncFieldDef('url', 'Project URL', hint: 'https://xxxx.supabase.co'),
    SyncFieldDef('anonKey', 'Anon Key', obscure: true),
    SyncFieldDef('table', '表名', defaultValue: 'wuhece_backups'),
  ],
  's3': [
    SyncFieldDef('endpoint', 'Endpoint', hint: 'https://s3.amazonaws.com 或 R2 / MinIO 地址'),
    SyncFieldDef('region', 'Region', defaultValue: 'auto'),
    SyncFieldDef('accessKey', 'Access Key'),
    SyncFieldDef('secretKey', 'Secret Key', obscure: true),
    SyncFieldDef('bucket', '存储桶'),
    SyncFieldDef('objectPath', '对象路径', defaultValue: 'wuhece/backup.json'),
  ],
  'boxbook': [
    SyncFieldDef('url', '服务器地址', hint: 'http://192.168.1.10:8800'),
    SyncFieldDef('user', '用户名'),
    SyncFieldDef('password', '密码', obscure: true),
  ],
};

const Map<String, String> kProviderSub = {
  'baidu': '百度网盘开放平台 · 数据存入网盘专属目录 /apps/应用名 · 需自备 AppKey',
  'webdav': '坚果云 / 群晖 / 绿联 / Nextcloud（标准 WebDAV 协议）',
  'supabase': '开源后端 · 免费额度充足 · 无 NAS 的跨平台方案',
  's3': 'AWS S3 / Cloudflare R2 / MinIO · 免费额度大 · 灵活配置',
  'boxbook': '自托管服务端 · 多用户与共享物品册 · Docker 一键部署',
};

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late SyncSettings _settings;
  final Map<String, TextEditingController> _ctrls = {};
  List<BoxBookBook> _boxBooks = [];
  String _busy = '';
  String _lastSyncAt = '';
  bool _autoSync = false;
  String _baiduNickname = '';

  AppStore get store => AppStore.instance;

  @override
  void initState() {
    super.initState();
    _settings = SyncSettings.load(store.prefs);
    _lastSyncAt = SyncService.lastSyncAt(store.prefs) ?? '';
    _autoSync = store.prefs.getBool(SyncService.autoSyncKey) ?? false;
    for (final def in kProviderFields[_settings.provider] ?? const <SyncFieldDef>[]) {
      _ctrl(_settings.provider, def);
    }
    if (_settings.provider == 'boxbook' &&
        (_settings.fields['boxbook']?['token'] ?? '').isNotEmpty) {
      _refreshBoxBooks();
    }
    if (_settings.provider == 'baidu' &&
        (_settings.fields['baidu']?['accessToken'] ?? '').isNotEmpty) {
      _baiduNickname = _settings.fields['baidu']?['nickname'] ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String provider, SyncFieldDef def) {
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
    setState(() {
      _settings.provider = provider;
      for (final def in kProviderFields[provider] ?? const <SyncFieldDef>[]) {
        _ctrl(provider, def);
      }
    });
    SyncSettings.save(store.prefs, _settings);
  }

  /// 读取当前服务商的全部字段并持久化
  Map<String, String> _collectFields() {
    final defs = kProviderFields[_settings.provider] ?? const <SyncFieldDef>[];
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
      'baidu': ['appKey', 'secretKey'],
    }[_settings.provider] ?? const [];
    for (final key in requiredKeys) {
      if ((configured[key] ?? '').trim().isEmpty) {
        final def = (kProviderFields[_settings.provider] ?? const <SyncFieldDef>[])
            .firstWhere((d) => d.key == key, orElse: () => SyncFieldDef(key, key));
        if (mounted) toast(context, '请先填写「${def.label}」', error: true);
        return false;
      }
    }
    await SyncSettings.save(store.prefs, _settings);
    return true;
  }

  /// 构造后端；百度 token 自动续期时回写配置
  Future<SyncBackend?> _backend() async {
    if (!await _persist()) return null;
    if (_settings.provider == 'boxbook') {
      if (!mounted) return null;
      if ((_settings.fields['boxbook']?['token'] ?? '').isEmpty) {
        if (mounted) toast(context, '请先登录 BoxBook 服务端并选择物品册', error: true);
        return null;
      }
      if (_settings.bookId.isEmpty) {
        if (mounted) toast(context, '请先选择要同步的物品册', error: true);
        return null;
      }
    }
    if (_settings.provider == 'baidu' &&
        (_settings.fields['baidu']?['accessToken'] ?? '').isEmpty) {
      if (!mounted) return null;
      toast(context, '请先登录 百度网盘 完成授权', error: true);
      return null;
    }
    return buildBackend(_settings, onTokenRefreshed: _onBaiduTokenRefreshed);
  }

  void _onBaiduTokenRefreshed(String accessToken, String refreshToken, int expiresInSeconds) {
    final fields = _settings.fields['baidu'] ?? {};
    fields['accessToken'] = accessToken;
    fields['refreshToken'] = refreshToken;
    fields['expireAt'] = DateTime.now()
        .add(Duration(seconds: expiresInSeconds))
        .toIso8601String();
    _settings.fields['baidu'] = fields;
    SyncSettings.save(store.prefs, _settings);
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
        SyncLog.add(store.prefs, SyncLogEntry(
          at: DateTime.now().toIso8601String(),
          action: 'test',
          provider: _settings.provider,
          ok: true,
          message: '连接成功',
        ));
        if (mounted) toast(context, '连接成功');
      } on SyncException catch (err) {
        SyncLog.add(store.prefs, SyncLogEntry(
          at: DateTime.now().toIso8601String(),
          action: 'test',
          provider: _settings.provider,
          ok: false,
          message: err.message,
        ));
        if (mounted) toast(context, err.message, error: true);
      }
    });
  }

  Future<void> _upload() async {
    final backend = await _backend();
    if (backend == null) return;
    await _run('upload', () async {
      final outcome = await SyncService.uploadBackup(store, backend, store.prefs, provider: _settings.provider);
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
      message: '将用云端备份覆盖本机的全部数据，本机新增内容会丢失（恢复前会自动拍一份本地快照）。确定继续吗？',
      confirmText: '覆盖恢复',
      danger: true,
    );
    if (!ok) return;
    await _run('download', () async {
      final outcome = await SyncService.downloadBackup(store, backend, store.prefs, provider: _settings.provider);
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
        decision = await SyncService.smartSync(store, backend, store.prefs, provider: _settings.provider);
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
              ? await SyncService.uploadBackup(store, backend, store.prefs, provider: _settings.provider)
              : await SyncService.downloadBackup(store, backend, store.prefs, provider: _settings.provider);
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

  /* ------------------------- 百度网盘设备码授权 ------------------------- */

  Future<void> _baiduLogin() async {
    if (!await _persist()) return;
    final backend = buildBackend(_settings, onTokenRefreshed: _onBaiduTokenRefreshed) as BaiduBackend;
    await _run('baiduLogin', () async {
      BaiduDeviceCode code;
      try {
        code = await backend.requestDeviceCode();
      } on SyncException catch (err) {
        if (mounted) toast(context, err.message, error: true);
        return;
      }
      if (!mounted) return;
      final authorized = await _showBaiduAuthorizeDialog(backend, code);
      if (!authorized || !mounted) return;
      // 拉取并缓存账号昵称（供「已授权账号」展示）
      try {
        _baiduNickname = await backend.fetchNickname();
        _settings.fields['baidu']?['nickname'] = _baiduNickname;
        await SyncSettings.save(store.prefs, _settings);
      } catch (_) {
        // 昵称拉取失败不阻断授权成功流程
      }
      if (!mounted) return;
      setState(() {});
      toast(context, '百度网盘授权成功');
    });
  }

  Future<bool> _showBaiduAuthorizeDialog(BaiduBackend backend, BaiduDeviceCode code) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BaiduAuthorizeDialog(backend: backend, code: code),
    ).then((v) => v ?? false);
  }

  Future<void> _baiduLogout() async {
    final fields = _settings.fields['baidu'] ?? {};
    fields
      ..remove('accessToken')
      ..remove('refreshToken')
      ..remove('expireAt')
      ..remove('nickname');
    _settings.fields['baidu'] = fields;
    await SyncSettings.save(store.prefs, _settings);
    if (mounted) setState(() => _baiduNickname = '');
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
    final defs = kProviderFields[provider] ?? const <SyncFieldDef>[];
    final isBox = provider == 'boxbook';
    final isBaidu = provider == 'baidu';

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
        title: Text('网盘同步', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 19),
            tooltip: '同步记录',
            onPressed: () => openSyncLogPage(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: pageContainer(
        context,
        children: [
          PageHeader(
            title: '网盘同步',
            sub: '数据同步到你自己的网盘或服务器',
          ),
          SectionCard(
            title: '同步服务商',
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
                SettingRow(
                  title: '启动自动同步',
                  desc: '每次打开应用时自动智能同步一次（冲突不自动处理，结果见同步记录）',
                  action: Switch(
                    value: _autoSync,
                    onChanged: (v) {
                      setState(() => _autoSync = v);
                      store.prefs.setBool(SyncService.autoSyncKey, v);
                    },
                  ),
                ),
                const Divider(height: 20),
                FormField2(
                  label: '同步至',
                  child: SelectField<String>(
                    value: provider,
                    items: [
                      for (final p in ['baidu', 'webdav', 'supabase', 's3', 'boxbook'])
                        DropdownMenuItem(value: p, child: Text(syncProviderLabel(p))),
                    ],
                    onChanged: (v) => _switchProvider(v ?? provider),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  kProviderSub[provider] ?? '',
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
                if (isBaidu) ..._baiduExtras(),
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
                if (isBaidu) ...[
                  const SizedBox(height: 10),
                  Text(
                    '使用前提：在 pan.baidu.com/union（百度网盘开放平台）注册开发者、实名认证并创建应用，'
                    '把应用详情页的 AppKey / SecretKey 填到上方，然后点「登录 百度网盘」在浏览器完成授权。'
                    '数据存放在网盘的应用专属目录，不会占用分享空间；授权 30 天自动续期。'
                    '上传覆盖前旧备份会自动复制到 history 目录，本地也会留存快照。',
                    style: TextStyle(fontSize: 11, color: context.gc.muted2, height: 1.6),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: kSectionGap),
          _logEntryCard(),
        ],
      ),
    );
  }

  /// 同步记录入口卡
  Widget _logEntryCard() {
    final logs = SyncLog.load(store.prefs);
    return SectionCard(
      title: '同步记录',
      sub: logs.isEmpty ? '还没有同步操作' : '最近：${SyncLog.actionLabel(logs.first.action)} · ${logs.first.message}',
      action: MiniBadge(label: '${logs.length} 条', color: context.gc.muted, bg: context.gc.bgDeep),
      child: OutlinedButton.icon(
        onPressed: () => openSyncLogPage(context),
        icon: const Icon(Icons.history, size: 14),
        label: const Text('查看全部同步记录'),
      ),
    );
  }

  List<Widget> _baiduExtras() {
    final token = _settings.fields['baidu']?['accessToken'] ?? '';
    final authorized = token.isNotEmpty;
    return [
      const Divider(height: 20),
      if (authorized)
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 16, color: context.gc.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已授权账号：${_baiduNickname.isEmpty ? '百度用户' : _baiduNickname}',
                style: TextStyle(fontSize: 13, color: context.gc.ink),
              ),
            ),
            TextButton(
              onPressed: _baiduLogout,
              child: const Text('退出登录'),
            ),
          ],
        )
      else ...[
        row([
          actionButton('baiduLogin', '登录 百度网盘', Icons.login, _baiduLogin, filled: true),
        ]),
        const SizedBox(height: 6),
        Text(
          '登录后在任意浏览器打开授权页、输入口令即可，无需安装百度网盘客户端。',
          style: TextStyle(fontSize: 11, color: context.gc.muted2),
        ),
      ],
    ];
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

/// 百度设备码授权弹窗：展示口令与授权链接，后台自动轮询
class _BaiduAuthorizeDialog extends StatefulWidget {
  const _BaiduAuthorizeDialog({required this.backend, required this.code});

  final BaiduBackend backend;
  final BaiduDeviceCode code;

  @override
  State<_BaiduAuthorizeDialog> createState() => _BaiduAuthorizeDialogState();
}

class _BaiduAuthorizeDialogState extends State<_BaiduAuthorizeDialog> {
  String _error = '';
  bool _polling = true;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    try {
      await widget.backend.pollForToken(widget.code);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _polling = false;
        _error = err is SyncException ? err.message : '授权失败：$err';
      });
    }
  }

  Future<void> _openUrl() async {
    final uri = Uri.parse(widget.code.verificationUrl.startsWith('http')
        ? widget.code.verificationUrl
        : 'https://${widget.code.verificationUrl}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, '无法打开浏览器，请手动复制链接到浏览器打开', error: true);
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code.userCode));
    if (mounted) toast(context, '口令已复制');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '登录 百度网盘',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第一步：打开授权页（任意浏览器均可）',
            style: TextStyle(fontSize: 12.5, color: context.gc.muted),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openUrl,
            icon: const Icon(Icons.open_in_new, size: 14),
            label: Text(widget.code.verificationUrl, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 14),
          Text(
            '第二步：在授权页输入口令',
            style: TextStyle(fontSize: 12.5, color: context.gc.muted),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.gc.primaryWeak,
              borderRadius: BorderRadius.circular(10),
            ),
            child: GestureDetector(
              onTap: _copyCode,
              child: Text(
                widget.code.userCode,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: context.gc.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _copyCode,
              icon: const Icon(Icons.copy, size: 13),
              label: const Text('复制口令', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 4),
          if (_polling)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('等待你在浏览器完成授权…', style: TextStyle(fontSize: 12.5, color: context.gc.muted)),
              ],
            )
          else ...[
            Text(_error, style: TextStyle(fontSize: 12.5, color: context.gc.danger)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _polling = true;
                  _error = '';
                });
                _poll();
              },
              child: const Text('重试轮询'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
      ],
    );
  }
}
