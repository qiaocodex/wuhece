/// Phase E 功能测试：BoxBook 客户端 / S3 SigV4 / 多服务商配置
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/sync/s3_sigv4.dart';
import 'package:guiwu/services/sync/sync_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BoxBook 客户端（对接假服务端）', () {
    late HttpServer server;
    late String base;
    String bookData = '';

    setUp(() async {
      bookData = '';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        var status = 200;
        var out = '{}';
        final route = '${request.method} ${request.uri.path}';
        switch (route) {
          case 'POST /api/login':
            final d = jsonDecode(body) as Map<String, dynamic>;
            if (d['username'] == 'demo' && d['password'] == 'pass') {
              out = jsonEncode({'token': 'tok-1', 'username': 'demo'});
            } else {
              status = 401;
              out = jsonEncode({'error': '用户名或密码错误'});
            }
          case 'GET /api/books':
            if (request.headers.value('authorization') != 'Bearer tok-1') {
              status = 401;
            } else {
              out = jsonEncode({
                'books': [
                  {
                    'id': 1,
                    'name': '家庭物品册',
                    'role': 'owner',
                    'ownerName': 'demo',
                    'memberCount': 1,
                  }
                ],
              });
            }
          case 'PUT /api/books/1/data':
            if (request.headers.value('authorization') != 'Bearer tok-1') {
              status = 401;
            } else {
              bookData = (jsonDecode(body) as Map)['content'] as String;
              out = jsonEncode({'ok': true, 'updatedAt': '2026-11-22T00:00:00Z'});
            }
          case 'GET /api/books/1/data':
            out = jsonEncode({
              'content': bookData,
              'updatedAt': '2026-11-22T00:00:00Z',
              'writerName': 'demo',
            });
          default:
            status = 404;
        }
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(out);
        await request.response.flush();
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('登录成功返回 token，错误密码返回 401 提示', () async {
      final token = await BoxBookBackend.login(
        serverUrl: base,
        username: 'demo',
        password: 'pass',
      );
      expect(token, 'tok-1');

      expect(
        () => BoxBookBackend.login(serverUrl: base, username: 'demo', password: 'bad'),
        throwsA(isA<SyncException>()),
      );
    });

    test('listBooks 解析书本', () async {
      final books = await BoxBookBackend.listBooks(serverUrl: base, token: 'tok-1');
      expect(books.length, 1);
      expect(books.first.id, 1);
      expect(books.first.name, '家庭物品册');
      expect(books.first.canWrite, isTrue);
    });

    test('upload / download 闭环', () async {
      final backend = BoxBookBackend(serverUrl: base, token: 'tok-1', bookId: 1);
      const content = '{"items":[1,2],"exportedAt":"2026-11-22T00:00:00Z"}';
      await backend.upload(content);
      expect(await backend.download(), content);
    });

    test('download 空物品册返回 null', () async {
      final backend = BoxBookBackend(serverUrl: base, token: 'tok-1', bookId: 1);
      expect(await backend.download(), isNull);
    });
  });

  group('S3 SigV4', () {
    test('相同输入产生相同且格式正确的签名', () {
      Map<String, String> sign() => S3SigV4.sign(
            method: 'GET',
            uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
            region: 'us-east-1',
            accessKey: 'AKIAIOSFODNN7EXAMPLE',
            secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
            payload: utf8.encode(''),
            now: DateTime.utc(2013, 5, 24),
          );

      final a = sign();
      final b = sign();
      expect(a['Authorization'], b['Authorization']);
      expect(a['Authorization'], startsWith('AWS4-HMAC-SHA256 Credential='));
      expect(a['Authorization'], contains('/20130524/us-east-1/s3/aws4_request, SignedHeaders='));
      expect(a['x-amz-date'], '20130524T000000Z');
      final auth = a['Authorization']!;
      final sig = auth.substring(auth.indexOf('Signature=') + 'Signature='.length);
      expect(sig.length, 64);
    });
  });

  group('多服务商配置', () {
    test('新格式读写 + BoxBook 字段', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SyncSettings()
        ..provider = 'boxbook'
        ..fields = {
          'boxbook': {'url': 'http://ip:8800', 'user': 'demo', 'password': 'pass', 'token': 'tok-1'},
        }
        ..bookId = '1'
        ..bookName = '家庭物品册';
      await SyncSettings.save(prefs, settings);

      final loaded = SyncSettings.load(prefs);
      expect(loaded.provider, 'boxbook');
      expect(loaded.fields['boxbook']?['token'], 'tok-1');
      expect(loaded.bookId, '1');
    });

    test('v1.2 旧 WebDAV 配置自动迁移', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guiwu.sync.config', jsonEncode({
        'url': 'https://dav.jianguoyun.com/dav/',
        'user': 'old@x.com',
        'password': 'app-pass',
        'remotePath': '/wuhece/backup.json',
      }));
      final loaded = SyncSettings.load(prefs);
      expect(loaded.provider, 'webdav');
      expect(loaded.fields['webdav']?['url'], 'https://dav.jianguoyun.com/dav/');
      expect(loaded.fields['webdav']?['password'], 'app-pass');
    });
  });
}
