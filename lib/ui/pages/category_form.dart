/// 分类表单：新增 / 编辑（对应 Web 版 settings.js 的 openCategoryForm）
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 打开分类表单（category 为空表示新增）
Future<void> openCategoryForm(BuildContext context, [Category? category]) {
  return showResponsive<void>(
    context,
    maxWidth: 440,
    builder: (_) => _CategoryFormBody(category: category),
  );
}

class _CategoryFormBody extends StatefulWidget {
  const _CategoryFormBody({this.category});

  final Category? category;

  @override
  State<_CategoryFormBody> createState() => _CategoryFormBodyState();
}

class _CategoryFormBodyState extends State<_CategoryFormBody> {
  late final TextEditingController _nameCtrl;
  late String _color;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category?.name ?? '');
    _color = widget.category?.color ?? kCategoryPalette.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final store = AppStore.instance;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      toast(context, '请填写分类名称', error: true);
      return;
    }
    if (widget.category != null) {
      store.updateCategory(widget.category!.id, name: name, color: _color);
      toast(context, '分类已更新');
    } else {
      store.addCategory(name, _color);
      toast(context, '分类已创建');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: widget.category != null ? '编辑分类' : '新增分类',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: Text(widget.category != null ? '保存' : '创建')),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormField2(
            label: '分类名称 *',
            child: TextField(
              controller: _nameCtrl,
              maxLength: 20,
              autofocus: widget.category == null,
              decoration: const InputDecoration(hintText: '例如：厨房用品', counterText: ''),
            ),
          ),
          const SizedBox(height: 14),
          FormField2(
            label: '标识颜色',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kCategoryPalette)
                  InkWell(
                    onTap: () => setState(() => _color = c),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: hexToColor(c),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _color == c ? GColors.ink : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _color == c
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
