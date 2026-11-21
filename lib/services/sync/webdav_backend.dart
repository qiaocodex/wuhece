/// WebDAV 同步后端（坚果云 / 群晖 / 绿联 / Nextcloud 等）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:webdav_client_plus/webdav_client_plus.dart';

import 'sync_backend.dart';

class WebDavBackend implements SyncBackend {
  WebDavBackend(this.config);

  final SyncConfig config;
  WebdavClient? _client;

  String get _baseUrl => config.url.endsWith('/') ? config.url : '${config.url}/';

  WebdavClient get _impl =>
      _client ??= WebdavClient.basicAuth(
        url: _baseUrl,
        user: config.user,
        pwd: config.password,
      );

  /// 远程路径的目录部分（如 /wuhece/backup.json → /wuhece）
  String get _dirPath {
    final p = config.remotePath;
    final i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }

  @override
  Future<void> testConnection() async {
    try {
      await _impl.ping();
    } on DioException catch (e) {
      throw SyncException(_mapDioError(e));
    } catch (err) {
      throw SyncException('连接失败：$err');
    }
  }

  @override
  Future<void> upload(String content) async {
    try {
      await _ensureDir();
      final bytes = Uint8List.fromList(utf8.encode(content));
      await _impl.write(config.remotePath, bytes);
    } on DioException catch (e) {
      throw SyncException(_mapDioError(e));
    }
  }

  @override
  Future<String?> download() async {
    try {
      if (!await _impl.exists(config.remotePath)) return null;
      final bytes = await _impl.read(config.remotePath);
      return utf8.decode(bytes);
    } on DioException catch (e) {
      throw SyncException(_mapDioError(e));
    }
  }

  /// 逐级创建远程目录（已存在时服务器返回 405，忽略）
  Future<void> _ensureDir() async {
    final segments =
        _dirPath.split('/').where((s) => s.isNotEmpty).toList();
    var path = '';
    for (final seg in segments) {
      path += '/$seg';
      try {
        await _impl.mkdir(path);
      } on DioException {
        // 目录已存在等情况忽略
      }
    }
  }

  String _mapDioError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) {
      return '账号或密码错误（坚果云请使用「应用密码」，不是登录密码）';
    }
    if (code == 403) {
      return '没有访问权限，请检查账号权限或应用密码';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '连接超时，请检查网络与服务器地址';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '无法连接服务器，请检查地址与网络';
    }
    return '请求失败${code == null ? '' : '（HTTP $code）'}';
  }
}
