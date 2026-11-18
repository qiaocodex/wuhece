/// 示例数据：首次启动即可体验完整功能（与 Web 版 seed.js 保持一致）
library;

import '../models/models.dart';
import '../services/dates.dart';
import '../services/id.dart';

final kDefaultSettings = AppSettings(idleDays: 90, currency: '¥', owner: '我');

const _categories = [
  {'id': 'cat-clothes', 'name': '衣物鞋包', 'color': '#c97c4e'},
  {'id': 'cat-digital', 'name': '数码电子', 'color': '#4e7bc9'},
  {'id': 'cat-books', 'name': '书籍文具', 'color': '#7b6cc4'},
  {'id': 'cat-kitchen', 'name': '厨房用品', 'color': '#5c9a7a'},
  {'id': 'cat-home', 'name': '家居日用', 'color': '#b8933f'},
  {'id': 'cat-beauty', 'name': '美妆个护', 'color': '#bd5f7d'},
  {'id': 'cat-sport', 'name': '运动户外', 'color': '#3e968f'},
  {'id': 'cat-docs', 'name': '证件票据', 'color': '#8b8377'},
  {'id': 'cat-other', 'name': '其他', 'color': '#9a9a9a'},
];

const _spaces = [
  {'id': 'sp-bedroom', 'name': '卧室', 'type': 'room', 'parentId': null, 'capacity': 16},
  {'id': 'sp-closet', 'name': '衣柜', 'type': 'area', 'parentId': 'sp-bedroom', 'capacity': 6},
  {'id': 'sp-closet-top', 'name': '上层收纳箱', 'type': 'container', 'parentId': 'sp-closet', 'capacity': 4},
  {'id': 'sp-nightstand', 'name': '床头柜', 'type': 'area', 'parentId': 'sp-bedroom', 'capacity': 6},
  {'id': 'sp-living', 'name': '客厅', 'type': 'room', 'parentId': null, 'capacity': 22},
  {'id': 'sp-tv', 'name': '电视柜', 'type': 'area', 'parentId': 'sp-living', 'capacity': 10},
  {'id': 'sp-cabinet', 'name': '储物柜', 'type': 'area', 'parentId': 'sp-living', 'capacity': 8},
  {'id': 'sp-drawer', 'name': '抽屉 A', 'type': 'container', 'parentId': 'sp-cabinet', 'capacity': 6},
  {'id': 'sp-entry', 'name': '玄关', 'type': 'room', 'parentId': null, 'capacity': 8},
  {'id': 'sp-shoes', 'name': '鞋柜', 'type': 'area', 'parentId': 'sp-entry', 'capacity': 8},
  {'id': 'sp-kitchen', 'name': '厨房', 'type': 'room', 'parentId': null, 'capacity': 12},
  {'id': 'sp-hang', 'name': '吊柜', 'type': 'area', 'parentId': 'sp-kitchen', 'capacity': 4},
  {'id': 'sp-fridge', 'name': '冰箱', 'type': 'area', 'parentId': 'sp-kitchen', 'capacity': 2},
  {'id': 'sp-study', 'name': '书房', 'type': 'room', 'parentId': null, 'capacity': 16},
  {'id': 'sp-desk', 'name': '书桌抽屉', 'type': 'area', 'parentId': 'sp-study', 'capacity': 6},
  {'id': 'sp-shelf', 'name': '书架', 'type': 'area', 'parentId': 'sp-study', 'capacity': 10},
  {'id': 'sp-storage', 'name': '储物间', 'type': 'room', 'parentId': null, 'capacity': 12},
];

class _SeedItem {
  const _SeedItem({
    required this.name,
    required this.cat,
    required this.space,
    required this.price,
    required this.qty,
    required this.buy,
    required this.tags,
    this.uses = const [],
    required this.created,
    this.warranty = 0,
    this.status = 'in_use',
    this.lends = const [],
    this.note = '',
  });

  final String name;
  final String cat;
  final String? space;
  final double price;
  final int qty;
  final String buy;
  final List<String> tags;
  final List<int> uses;
  final int created;
  final int warranty;
  final String status;
  final List<int> lends;
  final String note;
}

const _rawItems = [
  _SeedItem(name: '羊毛双面大衣', cat: 'cat-clothes', space: 'sp-closet', price: 1299, qty: 1, buy: 'd420', tags: ['冬季', '通勤'], uses: [9, 46, 120], created: 430, note: '干洗后套上防尘袋挂在衣柜左侧。'),
  _SeedItem(name: '轻薄羽绒服', cat: 'cat-clothes', space: 'sp-closet-top', price: 899, qty: 1, buy: 'd800', tags: ['冬季'], uses: [210, 265], created: 810),
  _SeedItem(name: '缓震跑步鞋', cat: 'cat-clothes', space: 'sp-shoes', price: 599, qty: 1, buy: 'd260', warranty: 6, tags: ['运动'], uses: [2, 5, 9], created: 265),
  _SeedItem(name: '帆布托特包', cat: 'cat-clothes', space: 'sp-closet', price: 259, qty: 1, buy: 'd500', tags: ['通勤', '百搭'], uses: [160], created: 505),
  _SeedItem(name: 'MacBook Air M2', cat: 'cat-digital', space: 'sp-cabinet', price: 7999, qty: 1, buy: 'd480', warranty: 24, tags: ['办公', '主力设备'], uses: [0, 1, 2, 4], created: 480, note: '保修卡与发票放在书桌抽屉的证件收纳册里。'),
  _SeedItem(name: '索尼头戴降噪耳机', cat: 'cat-digital', space: 'sp-nightstand', price: 1899, qty: 1, buy: 'd300', warranty: 12, tags: ['通勤', '数码'], uses: [4, 18, 60], created: 300),
  _SeedItem(name: 'iPad Air 3', cat: 'cat-digital', space: 'sp-cabinet', price: 2588, qty: 1, buy: 'd1400', status: 'idle', tags: ['旧设备'], uses: [320], created: 1400, note: '已换新，考虑出二手或给家人使用。'),
  _SeedItem(name: '20000mAh 充电宝', cat: 'cat-digital', space: 'sp-drawer', price: 129, qty: 1, buy: 'd180', warranty: 12, tags: ['出行'], uses: [35, 70], created: 180),
  _SeedItem(name: '三体全集', cat: 'cat-books', space: 'sp-shelf', price: 168, qty: 1, buy: 'd1200', status: 'idle', tags: ['科幻', '藏书'], uses: [400], created: 1200),
  _SeedItem(name: '设计中的设计', cat: 'cat-books', space: 'sp-shelf', price: 89, qty: 1, buy: 'd600', tags: ['设计'], uses: [25], created: 600),
  _SeedItem(name: '凌美钢笔', cat: 'cat-books', space: 'sp-desk', price: 320, qty: 1, buy: 'd900', tags: ['礼物'], uses: [12, 40], created: 900),
  _SeedItem(name: '空气炸锅', cat: 'cat-kitchen', space: 'sp-hang', price: 599, qty: 1, buy: 'd640', warranty: 24, status: 'idle', tags: ['小家电'], uses: [130], created: 640),
  _SeedItem(name: '电饭煲', cat: 'cat-kitchen', space: 'sp-hang', price: 459, qty: 1, buy: 'd900', tags: ['小家电'], uses: [0, 1], created: 900),
  _SeedItem(name: '手冲咖啡豆', cat: 'cat-kitchen', space: 'sp-fridge', price: 128, qty: 2, buy: 'd12', tags: ['食品', '咖啡'], uses: [8], created: 12, note: '开封后 30 天内喝完。'),
  _SeedItem(name: '保温杯', cat: 'cat-kitchen', space: 'sp-hang', price: 179, qty: 1, buy: 'd400', tags: ['日常'], uses: [6], created: 400),
  _SeedItem(name: '保温杯（旧款）', cat: 'cat-kitchen', space: 'sp-hang', price: 99, qty: 1, buy: 'd1100', status: 'idle', tags: ['日常'], uses: [260], created: 1100),
  _SeedItem(name: '乳胶枕', cat: 'cat-home', space: 'sp-storage', price: 299, qty: 1, buy: 'd900', status: 'idle', tags: ['床品'], uses: [250], created: 900),
  _SeedItem(name: '空气净化器滤芯', cat: 'cat-home', space: 'sp-storage', price: 199, qty: 1, buy: 'd200', warranty: 6, status: 'idle', tags: ['耗材'], created: 200),
  _SeedItem(name: '折叠晾衣架', cat: 'cat-home', space: 'sp-storage', price: 159, qty: 1, buy: 'd500', tags: ['收纳'], uses: [28], created: 500),
  _SeedItem(name: '加湿器', cat: 'cat-home', space: 'sp-cabinet', price: 299, qty: 1, buy: 'd340', warranty: 12, tags: ['小家电'], uses: [16], created: 340),
  _SeedItem(name: '负离子吹风机', cat: 'cat-beauty', space: 'sp-nightstand', price: 399, qty: 1, buy: 'd700', warranty: 24, tags: ['个护'], uses: [3, 8], created: 700),
  _SeedItem(name: '修护精华液', cat: 'cat-beauty', space: 'sp-nightstand', price: 520, qty: 1, buy: 'd40', tags: ['护肤'], uses: [1, 2], created: 40),
  _SeedItem(name: '天然橡胶瑜伽垫', cat: 'cat-sport', space: 'sp-cabinet', price: 199, qty: 1, buy: 'd600', status: 'idle', tags: ['健身'], uses: [110], created: 600),
  _SeedItem(name: '双人露营帐篷', cat: 'cat-sport', space: 'sp-storage', price: 899, qty: 1, buy: 'd700', status: 'lent', tags: ['露营', '外借'], lends: [45], created: 700, note: '借给同事小陈，记得提醒归还。'),
  _SeedItem(name: '房产证与购房合同', cat: 'cat-docs', space: 'sp-desk', price: 0, qty: 1, buy: 'd2500', tags: ['重要'], created: 2500),
  _SeedItem(name: '保修卡与发票收纳册', cat: 'cat-docs', space: 'sp-drawer', price: 0, qty: 1, buy: 'd500', tags: ['重要', '票据'], uses: [30], created: 500),
  _SeedItem(name: '纸质家庭相册', cat: 'cat-other', space: 'sp-storage', price: 0, qty: 1, buy: 'd2000', status: 'idle', tags: ['纪念'], uses: [300], created: 2000),
  _SeedItem(name: 'iPhone 11（旧手机）', cat: 'cat-digital', space: null, price: 4200, qty: 1, buy: 'd1800', status: 'idle', tags: ['旧设备'], uses: [500], created: 1800, note: '数据已备份，可回收或作为备用机。'),
  _SeedItem(name: '未拆封快递纸箱', cat: 'cat-other', space: null, price: 0, qty: 1, buy: 'd3', tags: ['待归位'], created: 3),
];

/// `d420` → 420 天前的日期
String _date(String code) {
  if (code.startsWith('d')) return dateDaysAgo(int.parse(code.substring(1)));
  return code;
}

List<UsageLog> _buildLogs(_SeedItem raw) {
  final logs = <UsageLog>[];
  for (final days in raw.uses) {
    logs.add(UsageLog(id: uid('log'), type: 'use', at: isoDaysAgo(days)));
  }
  for (final days in raw.lends) {
    logs.add(UsageLog(id: uid('log'), type: 'lend', at: isoDaysAgo(days), note: '借出'));
  }
  logs.sort((a, b) => b.at.compareTo(a.at));
  return logs;
}

/// 生成一套完整的演示数据
Map<String, dynamic> seedData() {
  final items = <Item>[];
  for (var i = 0; i < _rawItems.length; i++) {
    final raw = _rawItems[i];
    final logs = _buildLogs(raw);
    final latest = logs.isNotEmpty ? logs.first.at : null;
    final created = isoDaysAgo(raw.created);
    items.add(Item(
      id: 'it-${(i + 1).toString().padLeft(2, '0')}',
      name: raw.name,
      categoryId: raw.cat,
      spaceId: raw.space,
      tags: raw.tags,
      quantity: raw.qty,
      price: raw.price,
      purchaseDate: _date(raw.buy),
      warrantyMonths: raw.warranty,
      status: raw.status,
      image: null,
      note: raw.note,
      logs: logs,
      createdAt: created,
      updatedAt: latest ?? created,
    ));
  }

  return {
    'items': items,
    'categories': _categories.map((c) => Category(id: c['id'] as String, name: c['name'] as String, color: c['color'] as String)).toList(),
    'spaces': _spaces.map((s) => Space(id: s['id'] as String, name: s['name'] as String, type: s['type'] as String, parentId: s['parentId'] as String?, capacity: s['capacity'] as int)).toList(),
    'settings': AppSettings(),
  };
}

/// 空白数据（清空全部数据后使用）
Map<String, dynamic> emptyData() {
  return {
    'items': <Item>[],
    'categories': <Category>[Category(id: 'cat-other', name: '未分类', color: '#8b8377')],
    'spaces': <Space>[],
    'settings': AppSettings(),
  };
}
