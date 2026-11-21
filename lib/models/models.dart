/// 数据模型：字段与 Web 版 `guiwu.data.v2` 的 JSON Schema 完全一致，
/// 因此 Web 版导出的 JSON 备份可以直接导入本应用（反之亦然）。
library;

/// 物品状态展示元数据（对应 Web 版 STATUS）
class StatusMeta {
  const StatusMeta(this.label, this.tone);
  final String label; // 在用 / 闲置 / 借出 / 已处理
  final String tone; // green / amber / blue / gray
}

const Map<String, StatusMeta> kStatusMeta = {
  'in_use': StatusMeta('在用', 'green'),
  'idle': StatusMeta('闲置', 'amber'),
  'lent': StatusMeta('借出', 'blue'),
  'discarded': StatusMeta('已处理', 'gray'),
};

/// 空间类型元数据（对应 Web 版 SPACE_TYPES）
class SpaceTypeMeta {
  const SpaceTypeMeta(this.label, this.icon);
  final String label;
  final String icon; // door / layers / archive，widgets 中映射为 Material 图标
}

const Map<String, SpaceTypeMeta> kSpaceTypeMeta = {
  'room': SpaceTypeMeta('房间', 'door'),
  'area': SpaceTypeMeta('区域', 'layers'),
  'container': SpaceTypeMeta('收纳单元', 'archive'),
};

/// 分类标识色色板（对应 Web 版 PALETTE）
const List<String> kCategoryPalette = [
  '#c97c4e',
  '#4e7bc9',
  '#7b6cc4',
  '#5c9a7a',
  '#b8933f',
  '#bd5f7d',
  '#3e968f',
  '#8b8377',
  '#9a9a9a',
];

/// 使用记录（use 使用 / lend 借出 / return 归还）
class UsageLog {
  UsageLog({required this.id, required this.type, required this.at, this.note = ''});

  String id;
  String type;
  String at; // ISO8601（UTC、Z 结尾，与 Web 版一致）
  String note;

  factory UsageLog.fromJson(Map<String, dynamic> json) => UsageLog(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'use',
        at: json['at'] as String? ?? '',
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'at': at, 'note': note};
}

/// 物品条目
class Item {
  Item({
    required this.id,
    required this.name,
    required this.categoryId,
    this.spaceId,
    List<String>? tags,
    this.quantity = 1,
    this.price = 0,
    this.purchaseDate,
    this.warrantyMonths = 0,
    this.status = 'in_use',
    this.image,
    this.note = '',
    this.disposedAt,
    this.disposalPrice,
    List<UsageLog>? logs,
    required this.createdAt,
    required this.updatedAt,
  })  : tags = tags ?? [],
        logs = logs ?? [];

  final String id;
  final String createdAt;
  String name;
  String categoryId;
  String? spaceId;
  List<String> tags;
  int quantity;
  double price;
  String? purchaseDate;
  int warrantyMonths;
  String status;
  String? image;
  String note;

  /// 处置信息（v1.4.0 扩展字段，Web 版旧数据缺省为 null）
  String? disposedAt;

  /// 处置残值（元，卖掉/回收所得）
  double? disposalPrice;
  List<UsageLog> logs;
  String updatedAt;

  /// 总价值 = 单价 × 数量
  double get value => price * quantity;

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        categoryId: json['categoryId'] as String? ?? '',
        spaceId: json['spaceId'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
        quantity: (json['quantity'] as num? ?? 1).toInt(),
        price: (json['price'] as num? ?? 0).toDouble(),
        purchaseDate: json['purchaseDate'] as String?,
        warrantyMonths: (json['warrantyMonths'] as num? ?? 0).toInt(),
        status: json['status'] as String? ?? 'in_use',
        image: json['image'] as String?,
        note: json['note'] as String? ?? '',
        disposedAt: json['disposedAt'] as String?,
        disposalPrice: (json['disposalPrice'] as num?)?.toDouble(),
        logs: (json['logs'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UsageLog.fromJson)
            .toList(),
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'categoryId': categoryId,
        'spaceId': spaceId,
        'tags': tags,
        'quantity': quantity,
        'price': price,
        'purchaseDate': purchaseDate,
        'warrantyMonths': warrantyMonths,
        'status': status,
        'image': image,
        'note': note,
        'disposedAt': disposedAt,
        'disposalPrice': disposalPrice,
        'logs': logs.map((l) => l.toJson()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// 深拷贝（表单草稿用：tags / logs 各自新建列表）
  Item copy() => Item(
        id: id,
        name: name,
        categoryId: categoryId,
        spaceId: spaceId,
        tags: List<String>.of(tags),
        quantity: quantity,
        price: price,
        purchaseDate: purchaseDate,
        warrantyMonths: warrantyMonths,
        status: status,
        image: image,
        note: note,
        disposedAt: disposedAt,
        disposalPrice: disposalPrice,
        logs: List<UsageLog>.of(logs),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// 把编辑后的可变字段写回目标对象（不动 id / createdAt）
  void applyTo(Item other) {
    other.name = name;
    other.categoryId = categoryId;
    other.spaceId = spaceId;
    other.tags = List<String>.of(tags);
    other.quantity = quantity;
    other.price = price;
    other.purchaseDate = purchaseDate;
    other.warrantyMonths = warrantyMonths;
    other.status = status;
    other.image = image;
    other.note = note;
    other.disposedAt = disposedAt;
    other.disposalPrice = disposalPrice;
  }
}

/// 收纳空间（room 房间 → area 区域 → container 收纳单元，可嵌套）
class Space {
  Space({
    required this.id,
    required this.name,
    this.type = 'area',
    this.parentId,
    this.capacity = 0,
  });

  final String id;
  String name;
  String type;
  String? parentId;
  int capacity;

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'area',
        parentId: json['parentId'] as String?,
        capacity: (json['capacity'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': type, 'parentId': parentId, 'capacity': capacity};
}

/// 分类
class Category {
  Category({required this.id, required this.name, this.color = '#8b8377'});

  final String id;
  String name;
  String color;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? '#8b8377',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

/// 使用偏好（对应 Web 版 DEFAULT_SETTINGS；ai 字段为本应用扩展，Web 版导入时缺省）
class AppSettings {
  AppSettings({
    this.idleDays = 90,
    this.currency = '¥',
    this.owner = '我',
    this.aiApiKey,
    this.aiModel = 'glm-4.5-flash',
    this.themeMode = 'system',
  });

  int idleDays;
  String currency;
  String owner;

  /// AI 对话（智谱开放平台）：key 仅存本机，随备份导出（含敏感信息，注意保管）
  String? aiApiKey;
  String aiModel;

  /// 深色模式：system / light / dark
  String themeMode;

  factory AppSettings.fromJson(Map<String, dynamic>? json) => AppSettings(
        idleDays: (json?['idleDays'] as num? ?? 90).toInt(),
        currency: json?['currency'] as String? ?? '¥',
        owner: json?['owner'] as String? ?? '我',
        aiApiKey: json?['aiApiKey'] as String?,
        aiModel: json?['aiModel'] as String? ?? 'glm-4.5-flash',
        themeMode: json?['themeMode'] as String? ?? 'system',
      );

  Map<String, dynamic> toJson() => {
        'idleDays': idleDays,
        'currency': currency,
        'owner': owner,
        'aiApiKey': aiApiKey,
        'aiModel': aiModel,
        'themeMode': themeMode,
      };
}

/// 分类统计行
class CategoryStat {
  const CategoryStat({required this.category, required this.count, required this.qty, required this.value});
  final Category category;
  final int count;
  final int qty;
  final double value;
}

/// 空间使用情况
class SpaceUsage {
  const SpaceUsage({required this.space, required this.count, required this.capacity, this.pct});
  final Space? space;
  final int count;
  final int capacity;

  /// 利用率（%，未设置容量时为 null）
  final int? pct;
}
