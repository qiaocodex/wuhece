/// CSV 解析与生成（对应 Web 版 utils.js 的 parseCSV / toCSV 及 settings.js 的导入映射）
library;

import '../models/models.dart';
import '../store/app_store.dart';
import 'format.dart';

/// 解析 CSV 文本（支持引号包裹、换行、BOM）
List<List<String>> parseCSV(String text) {
  final clean = text.replaceFirst(RegExp(r'^\ufeff'), '');
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;

  for (var i = 0; i < clean.length; i++) {
    final ch = clean[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < clean.length && clean[i + 1] == '"') {
          field.write('"');
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < clean.length && clean[i + 1] == '\n') i += 1;
      row.add(field.toString());
      if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
      field.clear();
    } else {
      field.write(ch);
    }
  }
  row.add(field.toString());
  if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// 生成 CSV 文本
String toCSV(List<List<Object?>> rows) {
  return rows.map((row) {
    return row.map((cell) {
      final text = cell?.toString() ?? '';
      return RegExp(r'[",\n]').hasMatch(text) ? '"${text.replaceAll('"', '""')}"' : text;
    }).join(',');
  }).join('\r\n');
}

/// 导入时的列别名（与 Web 版 CSV_COLUMNS 一致）
const Map<String, List<String>> kCsvColumns = {
  'name': ['名称', '物品名称', 'name'],
  'category': ['分类', '类别', 'category'],
  'space': ['存放位置', '位置', '空间', 'location'],
  'quantity': ['数量', 'quantity'],
  'price': ['单价', '价格', '价值', 'price'],
  'purchaseDate': ['购入日期', '购买日期', '日期', 'purchasedate'],
  'warranty': ['保修期(月)', '保修期', '保修月数', 'warranty'],
  'status': ['状态', 'status'],
  'tags': ['标签', 'tags'],
  'note': ['备注', 'note'],
};

const Map<String, String> kCsvStatus = {
  '在用': 'in_use',
  '闲置': 'idle',
  '借出': 'lent',
  '已处理': 'discarded',
};

/// CSV 导入的一行解析结果
class CsvRowDraft {
  CsvRowDraft({
    required this.name,
    required this.categoryName,
    required this.spaceId,
    required this.quantity,
    required this.price,
    required this.purchaseDate,
    required this.warrantyMonths,
    required this.status,
    required this.tags,
    required this.note,
  });

  final String name;
  final String categoryName;
  final String? spaceId;
  final int quantity;
  final double price;
  final String? purchaseDate;
  final int warrantyMonths;
  final String status;
  final List<String> tags;
  final String note;
}

double _toNumber(String value) {
  final n = double.tryParse(value.replaceAll(RegExp(r'[¥￥,\s]'), ''));
  return n ?? 0;
}

/// `2024.3.5` / `2024/3/5` → `2024-03-05`
String? normalizeDate(String raw) {
  final text = raw.trim().replaceAll('.', '-').replaceAll('/', '-');
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (m == null) return null;
  String p(String s) => s.padLeft(2, '0');
  return '${m.group(1)}-${p(m.group(2)!)}-${p(m.group(3)!)}';
}

/// 按路径标签匹配空间（完全匹配 → 末段名称匹配）
Space? resolveSpaceByLabel(String label) {
  final parts = label.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final target = parts.join(' / ');
  for (final s in AppStore.instance.spaces) {
    if (AppStore.instance.spacePathLabel(s.id) == target) return s;
  }
  Space? byName;
  for (final s in AppStore.instance.spaces) {
    if (s.name == parts.last) {
      byName = s;
      break;
    }
  }
  return byName;
}

/// 把 CSV 行映射为物品草稿（缺少「名称」列时抛 FormatException）
List<CsvRowDraft> mapCsvRows(List<String> header, List<List<String>> rows) {
  final index = <String, int>{};
  kCsvColumns.forEach((key, aliases) {
    index[key] = header.indexWhere(
      (h) => aliases.any((a) => a.toLowerCase() == h.trim().toLowerCase()),
    );
  });
  if ((index['name'] ?? -1) < 0) {
    throw const FormatException('CSV 缺少「名称」列');
  }

  String cell(List<String> row, String key) {
    final i = index[key] ?? -1;
    if (i < 0 || i >= row.length) return '';
    return row[i].trim();
  }

  final result = <CsvRowDraft>[];
  for (final row in rows) {
    final name = cell(row, 'name');
    if (name.isEmpty) continue;
    final space = resolveSpaceByLabel(cell(row, 'space'));
    final qty = _toNumber(cell(row, 'quantity')).round();
    result.add(CsvRowDraft(
      name: name,
      categoryName: cell(row, 'category'),
      spaceId: space?.id,
      quantity: qty < 1 ? 1 : qty,
      price: _toNumber(cell(row, 'price')) < 0 ? 0 : _toNumber(cell(row, 'price')),
      purchaseDate: normalizeDate(cell(row, 'purchaseDate')),
      warrantyMonths: max0(_toNumber(cell(row, 'warranty')).round()),
      status: kCsvStatus[cell(row, 'status')] ?? 'in_use',
      tags: parseTags(cell(row, 'tags').replaceAll(RegExp(r'\s*/\s*'), '，')),
      note: cell(row, 'note'),
    ));
  }
  return result;
}

int max0(int n) => n < 0 ? 0 : n;

/// 导出物品清单 CSV（带 BOM，Excel 直接打开不乱码）
String buildItemsCsv() {
  final store = AppStore.instance;
  const header = [
    '名称', '分类', '存放位置', '数量', '单价', '总价值',
    '购入日期', '保修期(月)', '状态', '标签', '备注',
  ];
  final rows = store.items.map<List<Object?>>((it) {
    final cat = store.getCategory(it.categoryId);
    return [
      it.name,
      cat?.name ?? '未分类',
      it.spaceId != null ? store.spacePathLabel(it.spaceId) : '未归位',
      it.quantity,
      it.price,
      it.value,
      it.purchaseDate ?? '',
      it.warrantyMonths,
      kStatusMeta[it.status]?.label ?? it.status,
      it.tags.join(' / '),
      it.note,
    ];
  }).toList();
  return '\ufeff${toCSV([header, ...rows])}';
}
