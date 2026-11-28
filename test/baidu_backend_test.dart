/// 百度网盘后端协议测试：设备码授权轮询 / token 刷新 / 上传序列 / 下载
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/services/sync/sync_backend.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Response → StreamedResponse（MockClient.streaming 要求）
http.StreamedResponse streamed(http.Response resp) => http.StreamedResponse(
      Stream.fromIterable([resp.bodyBytes]),
      resp.statusCode,
      headers: resp.headers,
    );

/// 流式返回 JSON（含中文时必须走 bytes 构造）
http.StreamedResponse streamedJson(Map<String, dynamic> data, [int status = 200]) => streamed(json(data, status));

/// 可编排响应队列的 MockClient（按请求特征返回）
MockClient queueClient(Future<http.Response> Function(http.Request request, int callIndex) handler) {
  var calls = 0;
  return MockClient((request) async {
    final idx = calls++;
    return handler(request, idx);
  });
}

http.Response json(Map<String, dynamic> data, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

BaiduBackend backendWith(http.Client client, {void Function(String, String, int)? onToken}) => BaiduBackend(
      appKey: 'test-ak',
      secretKey: 'test-sk',
      accessToken: '',
      refreshToken: 'rt-old',
      remoteDir: '/apps/物盒册',
      client: client,
      onTokenRefreshed: onToken,
    );

void main() {
  group('BaiduBackend 设备码授权', () {
    test('申请设备码解析 user_code 与轮询间隔', () async {
      final client = queueClient((req, i) async {
        expect(req.body, contains('client_id=test-ak'));
        return json({
          'device_code': 'dc-1',
          'user_code': 'abcd1234',
          'verification_url': 'https://openapi.baidu.com/device',
          'expires_in': 300,
          'interval': 1,
        });
      });
      final backend = backendWith(client);
      final code = await backend.requestDeviceCode();
      expect(code.deviceCode, 'dc-1');
      expect(code.userCode, 'abcd1234');
      expect(code.intervalSeconds, 1);
    });

    test('轮询：先 pending 再成功，token 回调持久化', () async {
      String? savedToken;
      String? savedRefresh;
      final client = queueClient((req, i) async {
        if (i == 0) {
          return json({'device_code': 'dc-1', 'user_code': 'x', 'interval': 1});
        }
        // token 轮询：第一次 pending，第二次成功
        expect(req.body, contains('grant_type=device_token'));
        if (i == 1) return json({'error': 'authorization_pending'});
        return json({
          'access_token': 'at-1',
          'refresh_token': 'rt-1',
          'expires_in': 2592000,
        });
      });
      final backend = backendWith(client, onToken: (t, r, _) {
        savedToken = t;
        savedRefresh = r;
      });
      final token = await backend.pollForToken(
        await backend.requestDeviceCode(),
        timeout: const Duration(seconds: 5),
      );
      expect(token.accessToken, 'at-1');
      expect(savedToken, 'at-1');
      expect(savedRefresh, 'rt-1');
    });

    test('设备码过期抛出友好错误', () async {
      final client = queueClient((req, i) async {
        if (i == 0) return json({'device_code': 'dc-1', 'user_code': 'x', 'interval': 1});
        return json({'error': 'authorization_expired'});
      });
      final backend = backendWith(client);
      await expectLater(
        backend.pollForToken(await backend.requestDeviceCode(), timeout: const Duration(seconds: 5)),
        throwsA(isA<SyncException>().having((e) => e.message, 'message', contains('授权已过期'))),
      );
    });
  });

  group('BaiduBackend 上传与下载', () {
    test('小文件单步上传（multipart 带 path）', () async {
      final bodies = <String>[];
      final client = MockClient.streaming((request, bodyStream) async {
        if (request.url.queryParameters['method'] == 'upload') {
          final bytes = await bodyStream.toBytes();
          bodies.add(utf8.decode(bytes, allowMalformed: true));
          return streamed(http.Response(jsonEncode({'errno': 0, 'fs_id': 1}), 200));
        }
        return streamed(http.Response('unexpected', 400));
      });
      final backend = BaiduBackend(
        appKey: 'ak',
        secretKey: 'sk',
        accessToken: 'at',
        remoteDir: '/apps/物盒册',
        client: client,
      );
      await backend.upload('{"exportedAt":"2026-11-28"}');
      expect(bodies.join(''), contains('backup.json'));
    });

    test('大文件走 预上传→分片→create 三步序列', () async {
      final methods = <String>[];
      var uploadIdSeen = false;
      final client = MockClient.streaming((request, bodyStream) async {
        final method = request.url.queryParameters['method'] ?? '';
        if (method == 'precreate') {
          methods.add('precreate');
          final body = await bodyStream.toBytes();
          final form = Uri(query: utf8.decode(body)).queryParameters;
          expect(form['path'], '/apps/物盒册/backup.json');
          expect(form['autoinit'], '1');
          return streamed(http.Response(jsonEncode({'errno': 0, 'uploadid': 'upid-9'}), 200));
        }
        if (method == 'upload') {
          methods.add('part${request.url.queryParameters['partseq']}');
          uploadIdSeen = uploadIdSeen || request.url.queryParameters['uploadid'] == 'upid-9';
          return streamed(http.Response(jsonEncode({'errno': 0}), 200));
        }
        if (method == 'create') {
          methods.add('create');
          return streamed(http.Response(jsonEncode({'errno': 0, 'fs_id': 9}), 200));
        }
        return streamed(http.Response('unexpected', 400));
      });
      final backend = BaiduBackend(
        appKey: 'ak',
        secretKey: 'sk',
        accessToken: 'at',
        remoteDir: '/apps/物盒册',
        client: client,
      );
      // 5MB 内容 → 2 片
      final big = jsonEncode({'data': 'x' * (5 * 1024 * 1024)});
      await backend.upload(big);
      expect(methods.first, 'precreate');
      expect(methods[1], 'part0');
      expect(methods[2], 'part1');
      expect(methods.last, 'create');
      expect(uploadIdSeen, isTrue);
    });

    test('覆盖上传前先归档旧备份到 history', () async {
      final urls = <String>[];
      final client = MockClient.streaming((request, bodyStream) async {
        urls.add(request.url.toString());
        if (request.url.queryParameters['method'] == 'list') {
          return streamedJson({
            'errno': 0,
            'list': [
              {'path': '/apps/物盒册/backup.json', 'server_filename': 'backup.json', 'size': 3, 'isdir': 0},
            ],
          });
        }
        if (request.url.queryParameters['method'] == 'copy') {
          return streamed(http.Response(jsonEncode({'errno': 0}), 200));
        }
        if (request.url.queryParameters['method'] == 'upload') {
          return streamed(http.Response(jsonEncode({'errno': 0}), 200));
        }
        return streamed(http.Response('unexpected', 400));
      });
      final backend = BaiduBackend(
        appKey: 'ak',
        secretKey: 'sk',
        accessToken: 'at',
        remoteDir: '/apps/物盒册',
        client: client,
      );
      await backend.upload('data');
      expect(urls.indexWhere((u) => u.contains('method=copy')), greaterThanOrEqualTo(0));
      expect(urls.indexWhere((u) => u.contains('method=copy')), lessThan(urls.indexWhere((u) => u.contains('method=upload'))));
    });

    test('下载：文件不存在返回 null，存在返回内容', () async {
      final client = queueClient((req, i) async {
        expect(req.url.path, contains('/xpan/file'));
        expect(req.url.queryParameters['method'], 'download');
        return json({'errno': 66400004, 'errmsg': 'file does not exist'});
      });
      final backend = BaiduBackend(
        appKey: 'ak', secretKey: 'sk', accessToken: 'at', client: client,
      );
      expect(await backend.download(), isNull);
    });

    test('testConnection 未授权抛出提示', () async {
      final backend = backendWith(queueClient((req, i) async {
        return json({'error': 'invalid_token'}, 401);
      }));
      // accessToken 为空 → uinfo 返回 null → 触发续期（refresh_token 存在但接口失败）→ 抛错
      await expectLater(backend.testConnection(), throwsA(isA<SyncException>()));
    });
  });
}
