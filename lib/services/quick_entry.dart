/// 本地模板快路径：常见录入句式的正则解析 + 共用落库函数
///
/// 「买了体脂秤39.9」「昨天买了个保温杯 99 块，放厨房」这类高频句式
/// 无需等大模型思考，直接本地解析落库（毫秒级）；解析不了再回退 AI 对话。
/// [applyEntryToStore] 同时被 AI 的 add_item 工具调用，保证两条路径落库行为一致。
library;

import '../models/models.dart';
import '../store/app_store.dart';
import 'dates.dart';

/// 快速录入解析结果（字段尚未落库，交 [applyEntryToStore] 执行）
class QuickEntry {
  const QuickEntry({
    required this.name,
    required this.purchaseDate,
    this.price = 0,
    this.quantity = 1,
    this.warrantyMonths = 0,
    this.categoryName,
    this.spaceName,
  });

  final String name;
  final double price;
  final int quantity;
  final int warrantyMonths;
  final String purchaseDate;

  /// 猜测的分类名（可能不存在于分类列表，落库时按需创建/回落）
  final String? categoryName;

  /// 提取的存放位置名（与空间列表做匹配，匹配不上则物品未归位）
  final String? spaceName;
}

/* ------------------------- 解析入口 ------------------------- */

/// 问句/非录入语义特征：命中即放弃快路径，交给 AI
final RegExp _questionRe = RegExp(
    r'？|\?|多少|怎么|什么|为什么|哪个|哪些|什么时候|几[个块天月年]|统计|总结|分析|建议|对比|查询|查一下|帮我查|保修期|还是|如果|值不值|亏|推荐'
    r'|卖|退货|收入|工资|报销|预算|多久|何时|(?:小时|分钟|秒钟?)');

/// 录入意图动词（宽松匹配，配合问句门控使用）
final RegExp _addVerbRe = RegExp(r'买了|买个|买一|买|购入|购得|入手|入了|收了|添置|囤了');

final RegExp _punctBothRe = RegExp(r'^[，,。．.！!、；;：:\s~～]+|[，,。．.！!、；;：:\s~～]+$');

/// 常见词 → 分类名（仅当分类列表里存在同名分类时才生效，不自动创建）
const Map<String, List<String>> _categoryHints = {
  '数码电子': [
    '手机', '电脑', '笔记本', '平板', '耳机', '音箱', '充电', '数据线', '键盘', '鼠标',
    '显示器', '摄像头', '路由器', '硬盘', 'U盘', '电视', '相机', '手环', '手表', '麦克风', '读卡器',
  ],
  '厨房用品': [
    '锅', '碗', '筷', '勺', '杯', '壶', '刀具', '砧板', '保鲜', '料理', '微波炉', '烤箱',
    '空气炸', '电饭煲', '榨汁', '蒸锅',
  ],
  '清洁用品': ['扫把', '拖把', '抹布', '清洁剂', '垃圾袋', '垃圾桶', '刷子', '除尘'],
  '洗护用品': ['洗发', '沐浴', '牙膏', '牙刷', '毛巾', '纸巾', '洗衣', '香皂', '护肤', '防晒'],
  '服饰鞋包': ['衣服', '上衣', '裤子', '外套', '鞋子', '袜子', '帽子', '围巾', '手套', '背包', '钱包', '皮带'],
  '家居用品': ['枕头', '被子', '床单', '收纳箱', '衣架', '台灯', '香薰', '花瓶', '挂画', '地毯', '晾衣'],
  '文具书籍': ['钢笔', '中性笔', '铅笔', '本子', '记事本', '书籍', '图书', '文件夹', '胶带', '橡皮'],
  '食品零食': ['零食', '咖啡', '茶叶', '大米', '面条', '食用油', '饮料', '坚果', '饼干', '水果', '牛奶'],
  '药品保健': ['药', '维生素', '保健品', '口罩', '体温计', '血压计', '创可贴'],
  '运动户外': ['哑铃', '瑜伽', '球拍', '跳绳', '健身', '跑步', '露营', '帐篷', '渔具', '自行车', '护膝'],
};

/// 尝试用本地规则解析一条录入指令；返回 null 表示交回 AI 处理。
QuickEntry? tryQuickEntry(String input, AppStore store) {
  var rest = input.trim();
  if (rest.isEmpty || rest.length > 60) return null;
  if (_questionRe.hasMatch(rest)) return null;

  final hasVerb = _addVerbRe.hasMatch(rest);
  final hasPriceToken = RegExp(r'\d').hasMatch(rest);
  // 无动词也放行短句 + 价格（如「体脂秤 39.9」，参考记账 App 的极简输入）
  if (!hasVerb && !(hasPriceToken && rest.length <= 16)) return null;

  final today = DateTime.now();

  /* ---- 1. 日期 ---- */
  var purchaseDate = toISODate();
  for (final pair in _datePatterns(today)) {
    final m = pair.$1.firstMatch(rest);
    if (m == null) continue;
    final d = pair.$2(m);
    if (d != null) {
      purchaseDate = toISODate(d);
      rest = rest.replaceFirst(m.group(0)!, ' ');
    }
    break;
  }

  /* ---- 2. 保修（先剥掉，避免「12个月」被当成数量/价格） ---- */
  var warrantyMonths = 0;
  final wNum = RegExp(r'(?:保修|质保)期?\s*(\d+)\s*(个?月|年)').firstMatch(rest);
  if (wNum != null) {
    warrantyMonths = wNum.group(2)!.startsWith('年') ? int.parse(wNum.group(1)!) * 12 : int.parse(wNum.group(1)!);
    rest = rest.replaceFirst(wNum.group(0)!, ' ');
  } else {
    final wCn = RegExp(r'(?:保修|质保)期?\s*([一二两三四五六七八九十]{1,3})\s*年').firstMatch(rest);
    if (wCn != null) {
      warrantyMonths = (_cnNum(wCn.group(1)!) ?? 1) * 12;
      rest = rest.replaceFirst(wCn.group(0)!, ' ');
    }
  }

  /* ---- 3. 价格（「花了 N 块」整体优先，其次「N 块」） ---- */
  var price = 0.0;
  final spent = RegExp(r'花了\s*(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(?:块钱|块|元|RMB|rmb)?').firstMatch(rest);
  final priceUnit = RegExp(r'(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(?:块钱|块|元|大洋|RMB|rmb)').allMatches(rest).toList();
  if (spent != null) {
    price = _toNum(spent.group(1)!);
    rest = rest.replaceFirst(spent.group(0)!, ' ');
  } else if (priceUnit.isNotEmpty) {
    price = _toNum(priceUnit.last.group(1)!);
    rest = rest.replaceFirst(priceUnit.last.group(0)!, ' ');
  }

  /* ---- 4. 数量 ---- */
  var quantity = 1;
  final qty = RegExp(r'([零一二两三四五六七八九十]{1,3}|\d+)\s*'
          r'(个|只|件|台|把|支|双|瓶|盒|包|本|套|罐|袋|箱|卷|条|张|部|辆|副|对|斤|公斤|克|千克|升|毫升|米)')
      .firstMatch(rest);
  if (qty != null) {
    final n = RegExp(r'^\d+$').hasMatch(qty.group(1)!) ? int.parse(qty.group(1)!) : _cnNum(qty.group(1)!);
    if (n != null && n >= 1 && n <= 999) {
      quantity = n;
      rest = rest.replaceFirst(qty.group(0)!, ' ');
    }
  }

  // 剩余唯一裸数字按价格处理（如「体脂秤 39.9」「买了2个收纳箱 30」）
  if (price <= 0) {
    final bare = RegExp(r'\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?').allMatches(rest).toList();
    if (bare.length == 1) {
      price = _toNum(bare.first.group(0)!);
      rest = rest.replaceFirst(bare.first.group(0)!, ' ');
    } else if (bare.length > 1) {
      return null; // 多个数字语义不明，交回 AI
    }
  }

  /* ---- 5. 位置（优先拿真实空间名匹配） ---- */
  String? spaceName;
  final spaceNames = store.flattenSpaces().map((s) => s.space.name).where((n) => n.length >= 2).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in spaceNames) {
    final m = RegExp('(放|摆|搁|收|塞|藏|丢)(在|进|到|入|于|回)?${RegExp.escape(name)}').firstMatch(rest);
    if (m != null) {
      spaceName = name;
      rest = rest.replaceFirst(m.group(0)!, ' ');
      break;
    }
  }
  if (spaceName == null) {
    final fallback = RegExp(r'(?:放到|放在|放进|放入|摆到|摆在|搁在|收纳到|收纳在|收到|塞到|放|摆|搁)\s*([^，,。！!？?\s\d的]{1,12}?)了?(?=[，,。！!？?\s]|$)').firstMatch(rest);
    if (fallback != null) {
      spaceName = fallback.group(1);
      rest = rest.replaceFirst(fallback.group(0)!, ' ');
    }
  }

  /* ---- 6. 品名：剥填充词后取剩余 ---- */
  rest = rest
      .replaceAll('一共', ' ')
      .replaceAll('共计', ' ')
      .replaceAll(_punctBothRe, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // 句尾动作词（「今天买羽毛球拍花了 50 块，录入一下」）
  rest = rest.replaceFirst(
      RegExp(r'(帮我)?(录入一下|录一下|记录一下|记一下|记一笔|登记一下|录入|记录|登记|帮我录|帮我记)$'), '').trim();
  rest = rest.replaceFirst(RegExp(r'帮我$'), '').trim();
  // 句首引导词与购买动词
  rest = rest.replaceFirst(RegExp('^(我|帮我)(把|给)?'), '').trim();
  rest = rest.replaceFirst(
      RegExp('^(记录一下|记一笔|录入一下|登记一下|记一下|记录|录入|登记|添加一个|新增一个|添加|新增)'), '').trim();
  rest = rest.replaceFirst(
      RegExp('^(买了个|买了一个|买了(一)?(双|副|对)|买个|买一[个只台把支双件瓶盒包本套]|买了|买|购入了|购入|入手了|入手|添置了|添置|收了|囤了|入了|进了一批|进了)'),
      '').trim();
  rest = rest.replaceFirst(RegExp('^的'), '').trim();
  // 句尾「买的」「了」等
  rest = rest.replaceFirst(RegExp(r'(买了?|购入了?|入手了?|收了|囤了|添置了)的?$'), '').trim();
  rest = rest.replaceFirst(RegExp(r'[了呗啊啦哦呀哈]$'), '').trim();
  // 剥词后残留的标点（「羽毛球拍 ，」等）
  rest = rest
      .replaceAll(RegExp(r'[，,。．!！?？、；;：:·・"“”「」『』（）()【】\[\]<>~～]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final name = rest.trim();
  if (name.isEmpty || name.length > 24) return null;
  if (RegExp(r'^[\d\s.]+$').hasMatch(name)) return null;
  if (_questionRe.hasMatch(name)) return null;

  /* ---- 7. 分类猜测 ---- */
  final guessedCategory = _guessCategory(name, input, store);

  return QuickEntry(
    name: name,
    price: price,
    quantity: quantity,
    warrantyMonths: warrantyMonths,
    purchaseDate: purchaseDate,
    categoryName: guessedCategory.isEmpty ? null : guessedCategory,
    spaceName: (spaceName == null || spaceName.isEmpty) ? null : spaceName,
  );
}

/* ------------------------- 落库（快路径与 AI 工具共用） ------------------------- */

/// 把解析好的字段写入物品库（AI 的 add_item 工具同样走这里）
Item applyEntryToStore(
  AppStore store, {
  required String name,
  required String purchaseDate,
  double price = 0,
  int quantity = 1,
  int warrantyMonths = 0,
  String? categoryName,
  String? spaceName,
  List<String> tags = const [],
  String note = '',
}) {
  // 分类列表为空时兜底建一个，避免物品落到无效分类
  if (store.categories.isEmpty) store.ensureCategory('其他');

  final cleanCategory = (categoryName ?? '').trim();
  final categoryId = cleanCategory.isNotEmpty
      ? (store.ensureCategory(cleanCategory) ?? _fallbackCategoryId(store))
      : _fallbackCategoryId(store);

  final cleanSpace = (spaceName ?? '').trim();
  String? spaceId;
  if (cleanSpace.isNotEmpty) {
    for (final s in store.spaces) {
      if (s.name == cleanSpace) {
        spaceId = s.id;
        break;
      }
    }
    spaceId ??= store.spaces.where((s) => s.name.contains(cleanSpace)).map((s) => s.id).firstOrNull;
    // 提取短语比空间名长（如「客厅电视柜」→ 空间「客厅」）
    spaceId ??= store.spaces.where((s) => cleanSpace.contains(s.name)).map((s) => s.id).firstOrNull;
  }

  final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(purchaseDate) ? purchaseDate : toISODate();

  return store.addItem(
    name: name,
    categoryId: categoryId,
    spaceId: spaceId,
    quantity: quantity,
    price: price,
    purchaseDate: date,
    warrantyMonths: warrantyMonths,
    tags: tags,
    note: note,
  );
}

String _fallbackCategoryId(AppStore store) =>
    store.categories.isNotEmpty ? store.categories.first.id : 'cat-other';

/* ------------------------- 内部小工具 ------------------------- */

double _toNum(String raw) => double.tryParse(raw.replaceAll(',', '')) ?? 0;

/// 简易中文数字（1~99）
int? _cnNum(String s) {
  const d = {'零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
  int? digit(String c) => d[c];
  if (s.length == 1) return digit(s) ?? (s == '十' ? 10 : null);
  if (s == '十') return 10;
  if (s.endsWith('十')) return digit(s.substring(0, 1)) == null ? null : digit(s.substring(0, 1))! * 10;
  if (s.startsWith('十')) return digit(s.substring(1)) == null ? null : 10 + digit(s.substring(1))!;
  if (s.contains('十')) {
    final parts = s.split('十');
    if (parts.length != 2 || parts[1].isEmpty) return null;
    final t = digit(parts[0]);
    final u = digit(parts[1]);
    if (t == null || u == null) return null;
    return t * 10 + u;
  }
  return null;
}

/// 日期口语模式（顺序即优先级：先长后短）
List<(RegExp, DateTime? Function(Match))> _datePatterns(DateTime today) {
  DateTime recentWeekday(int w, {int extraWeeks = 0}) {
    final diff = (today.weekday - w + 7) % 7;
    return DateTime(today.year, today.month, today.day - diff - 7 * extraWeeks);
  }

  DateTime clampDay(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay));
  }

  const wd = '([一二三四五六日天])';
  int? weekNum(String c) => '一二三四五六'.contains(c) ? '一二三四五六'.indexOf(c) + 1 : (c == '日' || c == '天' ? 7 : null);

  return [
    // 2026-11-20 / 2026年11月20日
    (
      RegExp(r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})[日号]?'),
      (m) => clampDay(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)),
    ),
    // 11月20号 / 3月5日
    (
      RegExp(r'(\d{1,2})月(\d{1,2})[日号]'),
      (m) => clampDay(today.year, int.parse(m.group(1)!), int.parse(m.group(2)!)),
    ),
    // 30号（需要日期语境，避免「9号电池」误判；超过今天视为上个月）
    (
      RegExp(r'(\d{1,2})[日号](?=[，,。\s的当]|买|购|入|收|拿|$)'),
      (m) {
        final day = int.parse(m.group(1)!);
        if (day < 1 || day > 31) return null;
        return day <= today.day ? clampDay(today.year, today.month, day) : clampDay(today.year, today.month - 1, day);
      }
    ),
    // 大前天 / 前天 / 昨天 / 今天
    (
      RegExp(r'大前天|前天|昨天|昨日|今日|今天'),
      (m) {
        const offsets = {'大前天': 3, '前天': 2, '昨天': 1, '昨日': 1, '今日': 0, '今天': 0};
        return DateTime(today.year, today.month, today.day - offsets[m.group(0)!]!);
      }
    ),
    // 3天前
    (
      RegExp(r'(\d{1,3})\s*天前'),
      (m) => DateTime(today.year, today.month, today.day - int.parse(m.group(1)!)),
    ),
    // 2个月前
    (
      RegExp(r'(\d{1,2})\s*个?月前'),
      (m) {
        final n = int.parse(m.group(1)!);
        return clampDay(today.year, today.month - n, today.day);
      }
    ),
    // 3周前 / 3个星期前
    (
      RegExp(r'(\d{1,2})\s*个?(?:周|星期)前'),
      (m) => DateTime(today.year, today.month, today.day - int.parse(m.group(1)!) * 7),
    ),
    // 上周二 / 上星期六
    (
      RegExp('上(?:周|星期)$wd'),
      (m) {
        final w = weekNum(m.group(1)!);
        return w == null ? null : recentWeekday(w, extraWeeks: 1);
      }
    ),
    // 上周 / 上个月 / 去年 / 前年
    (
      RegExp(r'上周|上星期|上个月|上月|去年|前年'),
      (m) {
        switch (m.group(0)!) {
          case '上周' || '上星期':
            return DateTime(today.year, today.month, today.day - 7);
          case '上个月' || '上月':
            return clampDay(today.year, today.month - 1, today.day);
          case '去年':
            return clampDay(today.year - 1, today.month, today.day);
          default:
            return clampDay(today.year - 2, today.month, today.day);
        }
      }
    ),
    // 周二 / 星期二（最近一个过去的周二）
    (
      RegExp('(?:周|星期)$wd'),
      (m) {
        final w = weekNum(m.group(1)!);
        return w == null ? null : recentWeekday(w);
      }
    ),
  ];
}

/// 分类猜测：先看已有分类名是否出现在原文，再用关键词表映射
String _guessCategory(String name, String input, AppStore store) {
  for (final c in store.categories) {
    if (c.name.length >= 2 && input.contains(c.name)) return c.name;
  }
  for (final entry in _categoryHints.entries) {
    if (entry.value.any((k) => name.contains(k)) &&
        store.categories.any((c) => c.name == entry.key)) {
      return entry.key;
    }
  }
  return '';
}
