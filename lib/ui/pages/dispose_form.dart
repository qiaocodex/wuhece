/// 处置表单：标记物品为已处理，可选填处置日期与残值
library;

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/dates.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 打开处置表单
Future<void> openDisposeForm(BuildContext context, Item item) {
  return showResponsive<void>(
    context,
    builder: (_) => _DisposeFormBody(item: item),
  );
}

class _DisposeFormBody extends StatefulWidget {
  const _DisposeFormBody({required this.item});

  final Item item;

  @override
  State<_DisposeFormBody> createState() => _DisposeFormBodyState();
}

class _DisposeFormBodyState extends State<_DisposeFormBody> {
  late final TextEditingController _priceCtrl;
  late String _disposedAt;
  bool _saving = false;

  AppStore get store => AppStore.instance;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.item.disposalPrice != null && widget.item.disposalPrice! > 0
          ? widget.item.disposalPrice.toString()
          : '',
    );
    _disposedAt = widget.item.disposedAt ?? toISODate();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_disposedAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 1),
      helpText: '选择处置日期',
    );
    if (picked != null) setState(() => _disposedAt = toISODate(picked));
  }

  void _submit() {
    if (_saving) return;
    final price = double.tryParse(_priceCtrl.text.trim().replaceAll(',', ''));
    setState(() => _saving = true);
    store.patchItem(widget.item.id, (it) {
      it.status = 'discarded';
      it.disposedAt = _disposedAt;
      it.disposalPrice = price != null && price < 0 ? null : price;
    });
    final salvageText = price != null && price > 0 ? '，回收残值 ¥${price.toString()}' : '';
    toast(context, '「${widget.item.name}」已标记为已处理$salvageText');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: '处置「${widget.item.name}」',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: GColors.danger),
          child: const Text('标记已处理'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '标记为已处理后，物品将从统计与整理建议中移除，使用记录仍保留。'
            '如卖出或回收，可填写残值用于回收率统计。',
            style: TextStyle(fontSize: 12, color: context.gc.muted, height: 1.6),
          ),
          const SizedBox(height: 16),
          FormField2(
            label: '处置日期',
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: GColors.muted),
                ),
                child: Text(
                  formatDate(_disposedAt),
                  style: TextStyle(fontSize: 13.5, color: context.gc.ink),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FormField2(
            label: '残值（元，可空）',
            hint: '卖出 / 回收所得，用于计算回收率',
            child: TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: '0'),
            ),
          ),
        ],
      ),
    );
  }
}
