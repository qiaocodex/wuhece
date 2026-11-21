/// 设置：数据管理、分类管理、偏好与关于（对应 Web 版 settings.js）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/csv.dart';
import '../../services/dates.dart';
import '../../services/file_io.dart' as file_io;
import '../../services/format.dart';
import '../../services/glm_chat.dart';
import '../../services/id.dart';
import '../../services/sync/sync_backend.dart';
import '../../services/sync/sync_service.dart';
import '../../services/sync/webdav_backend.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'category_form.dart';
import 'tags_page.dart';

part 'sync_section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.gc.bg,
        surfaceTintColor: context.gc.bg,
        scrolledUnderElevation: 0,
        title: Text('设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => pageContainer(
          context,
          children: [
            const PageHeader(title: '设置', sub: '数据备份、分类管理与使用偏好'),
            const _SyncSection(),
            const SizedBox(height: kSectionGap),
            _dataSection(context),
            const SizedBox(height: kSectionGap),
            const _AiSection(),
            const SizedBox(height: kSectionGap),
            _categorySection(context),
            const SizedBox(height: kSectionGap),
            _prefSection(context),
            const SizedBox(height: kSectionGap),
            _aboutSection(context),
          ],
        ),
      ),
    );
  }

  /* ------------------------- 数据管理 ------------------------- */

  Widget _dataSection(BuildContext context) {
    final store = AppStore.instance;
    final canPick = file_io.filePickSupported;
    final csvCount = store.items.length;

    return SectionCard(
      title: '数据管理',
      sub: '所有数据保存在本机，可随时备份或迁移',
      child: Column(
        children: [
          _SettingRow(
            title: '导出完整备份',
            desc: '包含物品、空间、分类与使用记录的 JSON 文件',
            action: OutlinedButton.icon(
              onPressed: () => _exportJson(context),
              icon: const Icon(Icons.download_outlined, size: 14),
              label: const Text('导出 JSON'),
            ),
          ),
          _SettingRow(
            title: '导出物品清单',
            desc: 'Excel / 表格软件可直接打开的 CSV，共 $csvCount 条',
            action: OutlinedButton.icon(
              onPressed: () => _exportCsv(context),
              icon: const Icon(Icons.download_outlined, size: 14),
              label: const Text('导出 CSV'),
            ),
          ),
          _SettingRow(
            title: '从 CSV 批量导入',
            desc: canPick
                ? '支持与本应用导出口径一致的表格，导入时只新增、不覆盖'
                : '手机端暂不支持文件导入，请使用 Web 或桌面端操作',
            action: OutlinedButton.icon(
              onPressed: canPick ? () => _importCsv(context) : null,
              icon: const Icon(Icons.upload_outlined, size: 14),
              label: const Text('导入 CSV'),
            ),
          ),
          _SettingRow(
            title: '导入备份',
            desc: '从 JSON 备份恢复，会覆盖当前全部数据（Web 版备份可直接使用）',
            action: OutlinedButton.icon(
              onPressed: canPick ? () => _importJson(context) : null,
              icon: const Icon(Icons.upload_outlined, size: 14),
              label: const Text('选择文件'),
            ),
          ),
          _SettingRow(
            title: '重置为示例数据',
            desc: '清空当前数据，载入一套完整的演示内容',
            action: OutlinedButton.icon(
              onPressed: () => _resetSeed(context),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重置'),
            ),
          ),
          _SettingRow(
            title: '清空全部数据',
            titleColor: context.gc.danger,
            desc: '删除本机保存的所有物品、空间与记录，不可撤销',
            action: OutlinedButton.icon(
              onPressed: () => _clearAll(context),
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('清空'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.gc.danger,
                side: BorderSide(color: context.gc.dangerWeak),
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

  Future<void> _exportCsv(BuildContext context) async {
    final ok = await file_io.exportTextFile(
      fileName: 'guiwu-items-${toISODate()}.csv',
      content: buildItemsCsv(),
      mime: 'text/csv',
    );
    if (ok && context.mounted) toast(context, 'CSV 已导出');
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

  Future<void> _importCsv(BuildContext context) async {
    final content = await file_io.pickTextFileContent(
      label: 'CSV 清单',
      extensions: ['csv'],
      mime: 'text/csv',
    );
    if (content == null || !context.mounted) return;
    try {
      final rows = parseCSV(content);
      if (rows.length < 2) throw const FormatException('CSV 中没有可导入的数据');
      final drafts = mapCsvRows(rows.first, rows.sublist(1));
      if (drafts.isEmpty) throw const FormatException('没有解析到有效的物品，请检查「名称」列');
      final ok = await confirmDialog(
        context,
        title: '导入 CSV',
        message: '将新增 ${drafts.length} 件物品，不会覆盖现有数据。确定导入吗？',
        confirmText: '导入',
      );
      if (!ok || !context.mounted) return;
      final store = AppStore.instance;
      final items = <Item>[];
      final now = nowIso();
      for (final d in drafts) {
        items.add(Item(
          id: uid('it'),
          name: d.name,
          categoryId: store.ensureCategory(d.categoryName) ?? 'cat-other',
          spaceId: d.spaceId,
          tags: d.tags,
          quantity: d.quantity,
          price: d.price,
          purchaseDate: d.purchaseDate,
          warrantyMonths: d.warrantyMonths,
          status: d.status,
          note: d.note,
          disposedAt: d.disposedAt,
          disposalPrice: d.disposalPrice,
          createdAt: now,
          updatedAt: now,
        ));
      }
      final count = store.addItemsBulk(items);
      toast(context, '已导入 $count 件物品');
    } catch (err) {
      toast(context, err is FormatException ? err.message : 'CSV 导入失败', error: true);
    }
  }

  Future<void> _resetSeed(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: '重置为示例数据',
      message: '当前所有数据会被示例内容替换，确定继续吗？',
      confirmText: '重置',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    AppStore.instance.resetToSeed();
    toast(context, '已恢复示例数据');
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: '清空全部数据',
      message: '将删除所有物品、空间与使用记录，且无法恢复。确定要清空吗？',
      confirmText: '确认清空',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    AppStore.instance.clearAll();
    toast(context, '数据已清空');
  }

  /* ------------------------- 分类管理 ------------------------- */

  Widget _categorySection(BuildContext context) {
    final store = AppStore.instance;
    final stats = store.categoryStats();
    return SectionCard(
      title: '分类管理',
      sub: '分类颜色会用于物品卡片与图表',
      action: OutlinedButton.icon(
        onPressed: () => openCategoryForm(context),
        icon: const Icon(Icons.add, size: 14),
        label: const Text('新增分类'),
      ),
      child: Column(
        children: [
          for (final cat in store.categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(color: hexToColor(cat.color), borderRadius: BorderRadius.circular(5)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(cat.name, style: TextStyle(fontSize: 13, color: context.gc.ink))),
                  Text(
                    '${stats.where((s) => s.category.id == cat.id).firstOrNull?.count ?? 0} 件',
                    style: TextStyle(fontSize: 12, color: context.gc.muted),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      onPressed: () => openCategoryForm(context, cat),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      color: context.gc.muted,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      onPressed: () => _deleteCategory(context, cat),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      color: context.gc.danger,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TagsPage()),
            ),
            icon: const Icon(Icons.sell_outlined, size: 14),
            label: Text('标签管理（${store.tagStats().length} 个）'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(BuildContext context, Category cat) async {
    final store = AppStore.instance;
    if (store.categories.length <= 1) {
      toast(context, '至少需要保留一个分类', error: true);
      return;
    }
    final count = store.items.where((it) => it.categoryId == cat.id).length;
    final ok = await confirmDialog(
      context,
      title: '删除分类',
      message: '确定删除「${cat.name}」吗？${count > 0 ? '其中 $count 件物品会移动到其他分类。' : ''}',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    store.deleteCategory(cat.id);
    toast(context, '分类已删除');
  }

  /* ------------------------- 使用偏好 ------------------------- */

  Widget _prefSection(BuildContext context) {
    final store = AppStore.instance;
    final used = store.storageBytes();
    final limit = 5 * 1024 * 1024;
    final imageCount = store.items.where((it) => it.image != null && it.image!.isNotEmpty).length;
    final pct = (used / limit * 100).clamp(0, 100).round();

    return SectionCard(
      title: '使用偏好',
      sub: '外观与整理建议的判定规则',
      child: Column(
        children: [
          _SettingRow(
            title: '深色模式',
            desc: '跟随系统 / 浅色 / 深色（当前 ${_themeModeLabel(store.settings.themeMode)}）',
            action: SelectField<String>(
              value: store.settings.themeMode,
              items: const [
                DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                DropdownMenuItem(value: 'light', child: Text('浅色')),
                DropdownMenuItem(value: 'dark', child: Text('深色')),
              ],
              onChanged: (v) {
                if (v == null) return;
                AppStore.instance.updateSettings(themeMode: v);
                toast(context, '外观已更新');
              },
            ),
          ),
          _SettingRow(
            title: '闲置判定天数',
            desc: '超过这个天数未记录使用，就提示整理（当前 ${store.settings.idleDays} 天）',
            // 固定宽度：下拉不能直接放进无界宽度的 Row
            action: SizedBox(
              width: 132,
              child: SelectField<int>(
                value: store.settings.idleDays,
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 天')),
                  DropdownMenuItem(value: 60, child: Text('60 天')),
                  DropdownMenuItem(value: 90, child: Text('90 天')),
                  DropdownMenuItem(value: 120, child: Text('120 天')),
                  DropdownMenuItem(value: 180, child: Text('180 天')),
                  DropdownMenuItem(value: 365, child: Text('365 天')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  AppStore.instance.updateSettings(idleDays: v);
                  toast(context, '偏好已更新');
                },
              ),
            ),
          ),
          _SettingRow(
            title: '数据存储',
            desc: '已使用 ${bytesText(used)} · ${store.items.length} 条物品记录',
            action: Text(
              '$imageCount 张图片',
              style: TextStyle(fontSize: 12, color: context.gc.muted),
            ),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 7,
                  backgroundColor: context.gc.bgDeep,
                  valueColor: AlwaysStoppedAnimation(pct >= 80 ? context.gc.danger : context.gc.primary),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('含 $imageCount 张图片', style: TextStyle(fontSize: 11, color: context.gc.muted2)),
                  Text('$pct%', style: TextStyle(fontSize: 11, color: context.gc.muted2)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(String mode) => switch (mode) {
        'light' => '浅色',
        'dark' => '深色',
        _ => '跟随系统',
      };

  /* ------------------------- 关于 ------------------------- */

  Widget _aboutSection(BuildContext context) {
    final store = AppStore.instance;
    return SectionCard(
      title: '关于物盒册',
      sub: '个人物品资产与收纳空间管理',
      action: MiniBadge(label: 'Flutter 1.0'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '物盒册帮助你盘点个人资产、规划收纳空间，并根据使用频率给出整理建议。'
            '应用完全离线运行，数据仅保存在本机，不会上传到任何服务器。'
            '支持 Android / iOS / Web / Windows / macOS 五端，数据格式与 Web 版互通，建议定期导出 JSON 备份。',
            style: TextStyle(fontSize: 12.5, color: context.gc.muted, height: 1.8),
          ),
          const Divider(),
          const SizedBox(height: 6),
          Text(
            '物品 ${store.items.length} 条 · 空间 ${store.spaces.length} 个 · 分类 ${store.categories.length} 个 · ${formatDate(toISODate())}',
            style: TextStyle(fontSize: 11.5, color: context.gc.muted2),
          ),
        ],
      ),
    );
  }
}

/* ------------------------- AI 助手 ------------------------- */

class _AiSection extends StatefulWidget {
  const _AiSection();

  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  late final TextEditingController _keyCtrl;
  late String _model;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final settings = AppStore.instance.settings;
    _keyCtrl = TextEditingController(text: settings.aiApiKey ?? '');
    _model = settings.aiModel;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    AppStore.instance.updateSettings(aiApiKey: _keyCtrl.text.trim(), aiModel: _model);
    toast(context, 'AI 配置已保存');
  }

  Future<void> _test() async {
    if (_testing) return;
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      toast(context, '请先填写 API Key', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      await GlmChatService.probe(apiKey: key, model: _model);
      if (mounted) toast(context, '连接成功，可以开始对话录入');
    } on GlmException catch (err) {
      if (mounted) toast(context, err.message, error: true);
    } catch (err) {
      if (mounted) toast(context, '测试失败：$err', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'AI 助手',
      sub: '自然语言对话录入物品（智谱 GLM）',
      action: MiniBadge(label: 'Beta', color: context.gc.accent, bg: context.gc.accentWeak),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormField2(
            label: 'API Key',
            child: TextField(
              controller: _keyCtrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: '粘贴智谱开放平台的 API Key'),
            ),
          ),
          const SizedBox(height: 12),
          FormField2(
            label: '模型',
            child: SelectField<String>(
              value: _model,
              items: [
                for (final m in GlmChatService.knownModels)
                  DropdownMenuItem(
                    value: m,
                    child: Text('$m${m == GlmChatService.defaultModel ? '（免费）' : ''}'),
                  ),
              ],
              onChanged: (v) => setState(() => _model = v ?? _model),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 14),
                label: const Text('保存配置'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_outlined, size: 14),
                label: const Text('测试连接'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '在 open.bigmodel.cn（智谱开放平台）注册后，于「API Keys」页面创建 Key；'
            'glm-4.5-flash 为免费模型。Key 仅保存在本机，请求由设备直连智谱，'
            '对话内容用于解析录入指令。Web 端可能受浏览器跨域策略限制，'
            '建议在桌面 / 移动端使用 AI 对话。',
            style: TextStyle(fontSize: 11, color: context.gc.muted2, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.desc, required this.action, this.titleColor});

  final String title;
  final String desc;
  final Widget action;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: titleColor ?? context.gc.ink),
                ),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: context.gc.muted, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Flexible 包裹：给非 flex 子项一个有界的宽松约束，避免下拉类控件崩溃
          Flexible(child: action),
        ],
      ),
    );
  }
}
