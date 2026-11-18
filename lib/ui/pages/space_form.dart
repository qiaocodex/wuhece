/// 空间表单：新增 / 编辑（对应 Web 版 spaces.js 的 openSpaceForm）
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../store/app_store.dart';
import '../widgets.dart';

/// 打开空间表单（editing 为空表示新增）
Future<void> openSpaceForm(
  BuildContext context, {
  String? parentId,
  String type = 'area',
  Space? editing,
}) {
  return showResponsive<void>(
    context,
    builder: (_) => _SpaceFormBody(parentId: parentId, type: type, editing: editing),
  );
}

class _SpaceFormBody extends StatefulWidget {
  const _SpaceFormBody({this.parentId, this.type = 'area', this.editing});

  final String? parentId;
  final String type;
  final Space? editing;

  @override
  State<_SpaceFormBody> createState() => _SpaceFormBodyState();
}

class _SpaceFormBodyState extends State<_SpaceFormBody> {
  final _nameCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  late String _type;
  String _parentId = '';

  @override
  void initState() {
    super.initState();
    final store = AppStore.instance;
    final editing = widget.editing;
    _nameCtrl.text = editing?.name ?? '';
    _capacityCtrl.text = editing != null && editing.capacity > 0 ? editing.capacity.toString() : '';
    _type = editing?.type ?? widget.type;
    _parentId = editing?.parentId ?? widget.parentId ?? '';

    // 名称太短时给个聚焦占位
    if (editing == null && store.spaces.isEmpty) {
      _type = _type == 'room' ? 'room' : _type;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final store = AppStore.instance;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      toast(context, '请填写空间名称', error: true);
      return;
    }
    final capacity = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
    final parentId = _parentId.isEmpty ? null : _parentId;
    if (parentId != null && store.getSpace(parentId)?.type == 'container') {
      toast(context, '收纳单元下不能再创建子空间', error: true);
      return;
    }

    if (widget.editing != null) {
      store.updateSpace(
        widget.editing!.id,
        Space(
          id: widget.editing!.id,
          name: name,
          type: parentId != null && _type == 'room' ? 'area' : _type,
          parentId: parentId,
          capacity: capacity < 0 ? 0 : capacity,
        ),
      );
      toast(context, '空间已更新');
    } else {
      store.addSpace(
        name: name,
        type: parentId != null && _type == 'room' ? 'area' : _type,
        parentId: parentId,
        capacity: capacity,
      );
      toast(context, '空间已创建');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final editing = widget.editing;
    final blocked = editing != null ? store.collectDescendantIds(editing.id) : <String>[];
    final parentOptions = store.spaces
        .where((s) => s.type != 'container' && !blocked.contains(s.id))
        .toList();

    final title = editing != null
        ? '编辑「${editing.name}」'
        : widget.parentId != null
            ? '新增收纳单元'
            : _type == 'room'
                ? '新增房间'
                : '新增空间';

    return FormScaffold(
      title: title,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: Text(editing != null ? '保存修改' : '创建')),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormField2(
            label: '空间名称 *',
            child: TextField(
              controller: _nameCtrl,
              maxLength: 30,
              autofocus: editing == null,
              decoration: const InputDecoration(hintText: '例如：卧室、衣柜、抽屉 A', counterText: ''),
            ),
          ),
          const SizedBox(height: 14),
          FormGrid(
            fullWidths: [false, false, true],
            children: [
              FormField2(
                label: '类型',
                child: SelectField<String>(
                  value: _type,
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('房间')),
                    DropdownMenuItem(value: 'area', child: Text('区域')),
                    DropdownMenuItem(value: 'container', child: Text('收纳单元')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              FormField2(
                label: '容量（可放件数）',
                child: TextField(
                  controller: _capacityCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '不限制可留空'),
                ),
              ),
              FormField2(
                label: '上级空间',
                hint: '收纳单元不能再包含下一级',
                child: SelectField<String>(
                  value: _parentId,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('无（作为独立房间）')),
                    for (final s in parentOptions)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          store.spacePathLabel(s.id, ' / '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _parentId = v ?? ''),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
