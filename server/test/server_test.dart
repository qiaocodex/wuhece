/// BoxBook 服务端端到端测试：注册/登录/物品册/共享/权限/数据闭环
///
/// 运行：cd server && dart test
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:boxbook_server/boxbook_server.dart';

Future<http.Response> request(
  String base,
  String method,
  String path, {
  String? token,
  Object? body,
}) {
  return http.Client().send(
    http.Request(method, Uri.parse('$base$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = token == null ? '' : 'Bearer $token'
      ..body = body == null ? '' : jsonEncode(body),
  ).then(http.Response.fromStream);
}

Future<Map<String, dynamic>> apiJson(
  String base,
  String method,
  String path, {
  String? token,
  Object? body,
  int? expectStatus,
}) async {
  final resp = await request(base, method, path, token: token, body: body);
  expect(resp.statusCode, expectStatus ?? 200, reason: resp.body);
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

Future<String> register(String base, String username, String password) async {
  final data = await apiJson(
    base,
    'POST',
    '/api/register',
    body: {'username': username, 'password': password},
  );
  return data['token'] as String;
}

Future<String> login(String base, String username, String password) async {
  final data = await apiJson(
    base,
    'POST',
    '/api/login',
    body: {'username': username, 'password': password},
  );
  return data['token'] as String;
}

void main() {
  late HttpServer server;
  late String base;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('boxbook-test');
    server = await startBoxBookServer(
      store: BoxStore('${tmpDir.path}/data.json')..load(),
      port: 0,
      webDir: 'web',
    );
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    await tmpDir.delete(recursive: true);
  });

  test('注册 → 登录 → 错误密码被拒', () async {
    final token = await register(base, 'alice', 'pass1234');
    expect(token, isNotEmpty);
    await login(base, 'alice', 'pass1234');

    final resp = await request(base, 'POST', '/api/login',
        body: {'username': 'alice', 'password': 'wrong'});
    expect(resp.statusCode, 401);
  });

  test('创建物品册 → 上传 → 下载闭环', () async {
    final token = await register(base, 'alice', 'pass1234');
    final book = await apiJson(base, 'POST', '/api/books',
        token: token, body: {'name': '家庭物品册'});
    final bookId = (book['book'] as Map)['id'];

    final content = jsonEncode({
      'items': [1, 2, 3],
      'exportedAt': '2026-11-21',
    });
    await apiJson(base, 'PUT', '/api/books/$bookId/data',
        token: token, body: {'content': content});

    final data = await apiJson(base, 'GET', '/api/books/$bookId/data', token: token);
    expect(data['content'], content);
    expect(data['writerName'], 'alice');
  });

  test('共享：editor 可写、viewer 只读', () async {
    final tokenA = await register(base, 'alice', 'pass1234');
    final book = await apiJson(base, 'POST', '/api/books',
        token: tokenA, body: {'name': '共享册'});
    final bookId = (book['book'] as Map)['id'];

    await register(base, 'bob', 'pass1234');
    await register(base, 'carol', 'pass1234');
    await apiJson(base, 'POST', '/api/books/$bookId/share',
        token: tokenA, body: {'username': 'bob', 'role': 'editor'});
    await apiJson(base, 'POST', '/api/books/$bookId/share',
        token: tokenA, body: {'username': 'carol', 'role': 'viewer'});

    final tokenBob = await login(base, 'bob', 'pass1234');
    final tokenCarol = await login(base, 'carol', 'pass1234');

    // bob（editor）上传
    await apiJson(base, 'PUT', '/api/books/$bookId/data',
        token: tokenBob, body: {'content': '{"from":"bob"}'});

    // carol（viewer）可读但不可写
    final data = await apiJson(base, 'GET', '/api/books/$bookId/data', token: tokenCarol);
    expect(data['content'], '{"from":"bob"}');
    final denied = await request(base, 'PUT', '/api/books/$bookId/data',
        token: tokenCarol, body: {'content': 'x'});
    expect(denied.statusCode, 403);
  });

  test('未登录访问被拒 / 权限外用户不可见他人物品册', () async {
    final resp = await http.get(Uri.parse('$base/api/books'));
    expect(resp.statusCode, 401);

    await register(base, 'alice', 'pass1234');
    await apiJson(base, 'POST', '/api/books',
        token: await login(base, 'alice', 'pass1234'), body: {'name': '私密册'});
    final tokenB = await register(base, 'mallory', 'pass1234');

    final books = await apiJson(base, 'GET', '/api/books', token: tokenB);
    expect((books['books'] as List).length, 0);
  });

  test('Web 管理页可访问', () async {
    final resp = await http.get(Uri.parse('$base/'));
    expect(resp.statusCode, 200);
    expect(resp.body, contains('BoxBook Cloud'));
  });
}
