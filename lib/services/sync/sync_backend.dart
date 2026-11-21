/// 云同步后端抽象。
///
/// v1 实现 WebDAV（覆盖坚果云 / 群晖 / 绿联 / Nextcloud）；
/// 后续 Supabase / S3 / iCloud / BoxBook Cloud 按同接口接入。
library;

/// 同步目标配置
class SyncConfig {
  const SyncConfig({
    required this.url,
    required this.user,
    required this.password,
    this.remotePath = '/wuhece/backup.json',
  });

  /// WebDAV 服务地址，如 https://dav.jianguoyun.com/dav/
  final String url;
  final String user;

  /// 坚果云请使用「应用密码」，不是登录密码
  final String password;

  /// 远端备份文件路径，默认 /wuhece/backup.json
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
