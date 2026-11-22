/// 云同步后端抽象与多服务商配置。
///
/// v1 实现 WebDAV（坚果云/群晖/绿联/Nextcloud）；v1.5.0 起扩展
/// Supabase / S3（AWS R2 / MinIO）/ BoxBook Cloud 自托管服务端；
/// iCloud 需 iOS 原生能力，暂缓。后续新后端按 [SyncBackend] 接口接入即可。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'boxbook_backend.dart';
import 's3_backend.dart';
import 'supabase_backend.dart';
import 'webdav_backend.dart';

export 'boxbook_backend.dart' show BoxBookBook, BoxBookBackend;
export 's3_backend.dart' show S3Backend;
export 'supabase_backend.dart' show SupabaseBackend;

/// 同步目标配置
class SyncConfig {
  const SyncConfig({
    required this.url,
    required this.user,
    required this.password,
    this.remotePath = '/wuhece/backup.json',
  });

  final String url;
  final String user;
  final String password;
  final String remotePath;

  bool get isConfigured =>
      url.trim().isNotEmpty && user.trim().isNotEmpty && password.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'url': url,
        'user': user,
        'password': password,
        'remotePath': remotePath,
      };

  factory SyncConfig.fromJson(Map<String, dynamic> json) => SyncConfig(
        url: json['url'] as String? ?? '',
        user: json['user'] as String? ?? '',
        password: json['password'] as String? ?? '',
        remotePath: json['remotePath'] as String? ?? '/wuhece/backup.json',
      );
}

/// 同步异常（message 为可直接展示的中文）
class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 同步后端接口
abstract class SyncBackend {
  /// 测试连接（失败抛 [SyncException]）
  Future<void> testConnection();

  /// 上传备份内容（覆盖远端）
  Future<void> upload(String content);

  /// 下载远端备份内容；远端不存在时返回 null
  Future<String?> download();
}

/// 同步服务商设置（多服务商，各自字段）
class SyncSettings {
  SyncSettings({this.provider = 'webdav', Map<String, Map<String, String>>? fields})
      : fields = fields ?? {};

  /// webdav / supabase / s3 / boxbook
  String provider = 'webdav';

  /// 各服务商的字段表：{provider: {key: value}}
  Map<String, Map<String, String>> fields;

  /// BoxBook 当前选中的物品册
  String bookId = '';
  String bookName = '';

  static const key = 'guiwu.sync.config';

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'fields': fields,
        'bookId': bookId,
        'bookName': bookName,
      };

  factory SyncSettings.fromJson(Map<String, dynamic> json) => SyncSettings(
        provider: json['provider'] as String? ?? 'webdav',
        fields: ((json['fields'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as Map?)?.cast<String, String>() ?? {}),
        ),
      )
        ..bookId = json['bookId']?.toString() ?? ''
        ..bookName = json['bookName'] as String? ?? '';

  /// 读取配置（自动迁移 v1.2 的 WebDAV 单服务商旧格式）
  static SyncSettings load(SharedPreferences prefs) {
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          if (map['provider'] != null) {
            return SyncSettings.fromJson(map);
          }
          // 旧版（v1.2）单 WebDAV 配置迁移
          return SyncSettings()
            ..provider = 'webdav'
            ..fields = {
              'webdav': {
                'url': map['url']?.toString() ?? '',
                'user': map['user']?.toString() ?? '',
                'password': map['password']?.toString() ?? '',
                'remotePath':
                    map['remotePath']?.toString() ?? '/wuhece/backup.json',
              },
            };
        }
      } catch (_) {
        // 解析失败按新配置处理
      }
    }
    return SyncSettings();
  }

  static Future<void> save(SharedPreferences prefs, SyncSettings settings) {
    return prefs.setString(key, jsonEncode(settings.toJson()));
  }
}

/// 按当前设置构造同步后端
SyncBackend buildBackend(SyncSettings settings) {
  String field(String provider, String key, [String fallback = '']) {
    final value = settings.fields[provider]?[key] ?? '';
    return value.isNotEmpty ? value : fallback;
  }

  switch (settings.provider) {
    case 'supabase':
      return SupabaseBackend(
        url: field('supabase', 'url'),
        anonKey: field('supabase', 'anonKey'),
        table: field('supabase', 'table', 'wuhece_backups'),
      );
    case 's3':
      return S3Backend(
        endpoint: field('s3', 'endpoint'),
        region: field('s3', 'region', 'auto'),
        accessKey: field('s3', 'accessKey'),
        secretKey: field('s3', 'secretKey'),
        bucket: field('s3', 'bucket'),
        objectPath: field('s3', 'objectPath', 'wuhece/backup.json'),
      );
    case 'boxbook':
      return BoxBookBackend(
        serverUrl: field('boxbook', 'url'),
        token: field('boxbook', 'token'),
        bookId: int.tryParse(settings.bookId) ?? 0,
      );
    default:
      return WebDavBackend(SyncConfig(
        url: field('webdav', 'url'),
        user: field('webdav', 'user'),
        password: field('webdav', 'password'),
        remotePath: field('webdav', 'remotePath', '/wuhece/backup.json'),
      ));
  }
}
