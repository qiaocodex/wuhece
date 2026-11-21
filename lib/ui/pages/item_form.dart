/// 物品表单：新增 / 编辑（对应 Web 版 items.js 的 openItemForm）
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/dates.dart';
import '../../services/format.dart';
import '../../services/image_service.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 打开物品表单（item 为空表示新增）
Future<void> openItemForm(BuildContext context, [Item? item]) {
  return showResponsive<void>(
    context,
    maxWidth: 680,
    builder: (_) => _ItemFormBody(item: item),
  );
}

class _ItemFormBody extends StatefulWidget {
  const _ItemFormBody({this.item});

  final Item? item;

  @override
  State<_ItemFormBody> createState() => _ItemFormBodyState();
}

class _ItemFormBodyState extends State<_ItemFormBody> {
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _warrantyCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late String _categoryId;
  late String _status;
  String _spaceId = '';
  String? _purchaseDate;
  String? _image;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final store = AppStore.instance;
    final item = widget.item;
    _nameCtrl.text = item?.name ?? '';
    _qtyCtrl.text = (item?.quantity ?? 1).toString();
    _priceCtrl.text = item != null && item.price > 0 ? _trimNum(item.price) : '';
    _warrantyCtrl.text = (item?.warrantyMonths ?? 0).toString();
    _tagsCtrl.text = (item?.tags ?? const []).join('，');
    _noteCtrl.text = item?.note ?? '';
    _categoryId = item?.categoryId ?? (store.categories.isNotEmpty ? store.categories.first.id : '');
    _status = item?.status ?? 'in_use';
    _spaceId = item?.spaceId ?? '';
    _purchaseDate = item?.purchaseDate ?? (item == null ? toISODate() : null);
    _image = item?.image;
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _warrantyCtrl.dispose();
    _tagsCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final url = await pickImageAsDataUrl(context);
    if (url != null) setState(() => _image = url);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _purchaseDate != null
        ? (DateTime.tryParse(_purchaseDate!) ?? now)
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 1),
      helpText: '选择购入日期',
    );
    if (picked != null) setState(() => _purchaseDate = toISODate(picked));
  }

  void _save() {
    if (_saving) return;
    final store = AppStore.instance;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      toast(context, '请填写物品名称', error: true);
      return;
    }
    final quantity = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final price = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final warranty = int.tryParse(_warrantyCtrl.text.trim()) ?? 0;
    final tags = parseTags(_tagsCtrl.text);
    final note = _noteCtrl.text.trim();

    setState(() => _saving = true);
    if (widget.item != null) {
      final edited = widget.item!.copy()
        ..name = name
        ..categoryId = _categoryId
        ..spaceId = _spaceId.isEmpty ? null : _spaceId
        ..tags = tags
        ..quantity = quantity < 1 ? 1 : quantity
        ..price = price < 0 ? 0 : price
        ..purchaseDate = _purchaseDate
        ..warrantyMonths = warranty < 0 ? 0 : warranty
        ..status = _status
        ..image = _image
        ..note = note;
      store.updateItem(widget.item!.id, edited);
      toast(context, '已保存修改');
    } else {
      store.addItem(
        name: name,
        categoryId: _categoryId,
        spaceId: _spaceId.isEmpty ? null : _spaceId,
        status: _status,
        quantity: quantity,
        price: price,
        purchaseDate: _purchaseDate,
        warrantyMonths: warranty,
        tags: tags,
        note: note,
        image: _image,
      );
      toast(context, '物品已入库');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final spaceRows = store.flattenSpaces();

    return FormScaffold(
      title: widget.item != null ? '编辑物品' : '新增物品',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: Text(widget.item != null ? '保存修改' : '保存物品')),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _photoSection(),
          const SizedBox(height: 14),
          FormField2(
            label: '物品名称 *',
            child: TextField(
              controller: _nameCtrl,
              maxLength: 60,
              decoration: const InputDecoration(hintText: '例如：羊毛大衣、MacBook Air', counterText: ''),
            ),
          ),
          const SizedBox(height: 14),
          FormGrid(
            fullWidths: [false, false, true, false, false, true, false, true],
            children: [
              FormField2(
                label: '分类',
                child: SelectField<String>(
                  value: _categoryId,
                  items: [
                    for (final c in store.categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
                ),
              ),
              FormField2(
                label: '状态',
                child: SelectField<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'in_use', child: Text('在用')),
                    DropdownMenuItem(value: 'idle', child: Text('闲置')),
                    DropdownMenuItem(value: 'lent', child: Text('借出')),
                    DropdownMenuItem(value: 'discarded', child: Text('已处理')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              ),
              FormField2(
                label: '存放位置',
                child: SelectField<String>(
                  value: _spaceId,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未归位')),
                    if (spaceRows.isEmpty)
                      const DropdownMenuItem(value: '__none__', child: Text('暂无空间，先去「空间」创建')),
                    for (final row in spaceRows)
                      DropdownMenuItem(
                        value: row.space.id,
                        child: Text(
                          '${'　' * row.depth}${row.depth > 0 ? '└ ' : ''}${row.space.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _spaceId = v ?? ''),
                ),
              ),
              FormField2(
                label: '数量',
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              FormField2(
                label: '单价（元）',
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '0'),
                ),
              ),
              FormField2(
                label: '购入日期',
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: context.gc.muted),
                    ),
                    child: Text(
                      _purchaseDate == null ? '未设置' : formatDate(_purchaseDate),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: _purchaseDate == null ? context.gc.muted2 : context.gc.ink,
                      ),
                    ),
                  ),
                ),
              ),
              FormField2(
                label: '保修期（月）',
                child: TextField(
                  controller: _warrantyCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              FormField2(
                label: '标签',
                hint: '标签可用于快速筛选与搜索',
                child: TextField(
                  controller: _tagsCtrl,
                  decoration: const InputDecoration(hintText: '用逗号分隔，例如：冬季，通勤，礼物'),
                ),
              ),
              FormField2(
                label: '备注',
                child: TextField(
                  controller: _noteCtrl,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(hintText: '记录保存方式、配件位置、借用情况等'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: context.gc.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.gc.lineStrong),
          ),
          child: _image != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: ItemThumb(image: _image, color: context.gc.muted, size: 86, iconSize: 30),
                )
              : Icon(Icons.photo_camera_outlined, size: 24, color: context.gc.muted2),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_camera_outlined, size: 14),
                    label: const Text('选择照片'),
                  ),
                  if (_image != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => setState(() => _image = null),
                      child: const Text('移除'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '图片会压缩后保存在本地，不上传服务器',
                style: TextStyle(fontSize: 11, color: context.gc.muted2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
