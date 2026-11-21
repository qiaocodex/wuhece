/// 标签管理页：批量重命名 / 删除标签、跳转物品库搜索
library;

import 'package:material_ui/material_ui.dart';

import '../../store/app_store.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      backgroundColor: GColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: GColors.bg,
        surfaceTintColor: GColors.bg,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '标签管理',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GColors.ink),
        ),
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
        builder: (context, _) {
          final tags = store.tagStats();
          return pageContainer(
            context,
            children: [
              PageHeader(
                title: '标签管理',
                sub: '共 ${tags.length} 个标签 · 重命名或删除会应用到所有物品',
              ),
              if (tags.isEmpty)
                const EmptyState(
                  icon: Icons.sell_outlined,
                  title: '还没有标签',
                  desc: '在新增/编辑物品时填写标签，这里就会自动汇总。',
                )
              else
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in tags.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              TagChip(text: entry.key),
                              const Spacer(),
                              Text(
                                '${entry.value} 件',
                                style: const TextStyle(fontSize: 12, color: GColors.muted),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: IconButton(
                                  tooltip: '搜索该标签',
                                  icon: const Icon(Icons.search, size: 15),
                                  color: GColors.muted,
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    ShellNav.maybeOf(context)?.searchItems(entry.key);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: IconButton(
                                  tooltip: '重命名',
                                  icon: const Icon(Icons.edit_outlined, size: 14),
                                  color: GColors.muted,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _rename(context, entry.key),
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline, size: 14),
                                  color: GColors.danger,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _remove(context, entry.key, entry.value),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, String oldTag) async {
    final store = AppStore.instance;
    final controller = TextEditingController(text: oldTag);
    final newName = await showResponsive<String>(
      context,
      maxWidth: 420,
      builder: (_) => FormScaffold(
        title: '重命名标签「$oldTag」',
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
        body: FormField2(
          label: '新名称',
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(hintText: '输入新的标签名', counterText: ''),
          ),
        ),
      ),
    );
    if (newName == null || !context.mounted) return;
    final clean = newName.trim();
    if (clean.isEmpty) {
      toast(context, '标签名不能为空', error: true);
      return;
    }
    if (clean == oldTag) return;
    store.renameTag(oldTag, clean);
    toast(context, '已将「$oldTag」重命名为「$clean」');
  }

  Future<void> _remove(BuildContext context, String tag, int count) async {
    final ok = await confirmDialog(
      context,
      title: '删除标签',
      message: '确定删除标签「$tag」吗？$count 件物品上的该标签会被移除，物品本身不受影响。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    AppStore.instance.removeTag(tag);
    toast(context, '标签「$tag」已删除');
  }
}
