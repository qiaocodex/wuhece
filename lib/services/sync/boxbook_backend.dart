/// BoxBook Cloud 同步后端：对接自托管服务端（server/ 目录，Docker 一键部署）
///
/// 支持多用户与共享物品册：登录后选择一本「物品册」（自己的或别人共享给你的），
/// 多台设备/多个用户同步同一本册子即实现共享。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_backend.dart';

class BoxBookBook {
  BoxBookBook({required this.id, required this.name, required this.role, required this.ownerName});

  final int id;
  final String name;
  final String role; // owner / editor / viewer
  final String ownerName;

  factory BoxBookBook.fromJson(Map<String, dynamic> json) => BoxBookBook(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? 'viewer',
        ownerName: json['ownerName'] as String? ?? '',
      );

  bool get canWrite => role == 'owner' || role == 'editor';
}

class BoxBookBackend implements SyncBackend {
  BoxBookBackend({
    required this.serverUrl,
    required this.token,
    required this.bookId,
  });

  /// 自托管服务端地址，如 http://192.168.1.10:8800
  final String serverUrl;
  final String token;
  final int bookId;

  Uri _uri(String path) {
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  String _mapError(Object err, int? statusCode) {
    if (statusCode == 401) return '登录已失效，请重新登录';
    if (statusCode == 403) return '没有该物品册的写入权限';
    if (statusCode == 404) return '物品册不存在';
    return 'BoxBook 请求失败：$err';
  }

  /// 账号密码登录，返回 token（设置页登录按钮）
  static Future<String> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    try {
      final response = await http
          .post(
            Uri.parse('$base/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SyncException(
          response.statusCode == 401
              ? '用户名或密码错误'
              : '登录失败（HTTP ${response.statusCode}）',
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return data['token'] as String? ?? '';
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('无法连接 BoxBook 服务端：$err');
    }
  }

  /// 注册账号（自托管服务端开放注册）
  static Future<String> register({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    try {
      final response = await http
          .post(
            Uri.parse('$base/api/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SyncException('注册失败（HTTP ${response.statusCode}）：${response.body}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return data['token'] as String? ?? '';
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('无法连接 BoxBook 服务端：$err');
    }
  }

  /// 获取可访问的物品册（自己的 + 共享给我的）
  static Future<List<BoxBookBook>> listBooks({
    required String serverUrl,
    required String token,
  }) async {
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    try {
      final response = await http
          .get(
            Uri.parse('$base/api/books'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SyncException('获取物品册失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final books = data['books'] as List? ?? const [];
      return books
          .whereType<Map<String, dynamic>>()
          .map(BoxBookBook.fromJson)
          .toList();
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('无法连接 BoxBook 服务端：$err');
    }
  }

  /// 新建物品册
  static Future<BoxBookBook> createBook({
    required String serverUrl,
    required String token,
    required String name,
  }) async {
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    try {
      final response = await http
          .post(
            Uri.parse('$base/api/books'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SyncException('创建物品册失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return BoxBookBook.fromJson((data['book'] ?? {}) as Map<String, dynamic>);
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('无法连接 BoxBook 服务端：$err');
    }
  }

  @override
  Future<void> testConnection() async {
    try {
      final response = await http
          .get(_uri('/api/books'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SyncException(_mapError(response, response.statusCode));
      }
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('无法连接 BoxBook 服务端：$err');
    }
  }

  @override
  Future<void> upload(String content) async {
    try {
      final response = await http
          .put(
            _uri('/api/books/$bookId/data'),
            headers: _headers,
            body: jsonEncode({'content': content}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw SyncException(_mapError(response, response.statusCode));
      }
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('上传失败：$err');
    }
  }

  @override
  Future<String?> download() async {
    try {
      final response = await http
          .get(_uri('/api/books/$bookId/data'), headers: _headers)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw SyncException(_mapError(response, response.statusCode));
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content = data['content']?.toString();
      return (content == null || content.isEmpty) ? null : content;
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('下载失败：$err');
    }
  }
}
