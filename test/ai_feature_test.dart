/// Phase A 功能测试：GLM 工具执行 / 搜索历史 / AI 页与首启引导冒烟
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guiwu/models/models.dart';
import 'package:guiwu/services/glm_chat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:guiwu/store/app_store.dart';
import 'package:guiwu/ui/pages/ai_chat_page.dart';
import 'package:guiwu/ui/shell.dart';
import 'package:guiwu/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = AppStore(prefs)..load();
  return store;
}

void main() {
  group('GLM 工具执行', () {
    test('add_item 完整参数', () async {
      final store = await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      final result = svc.executeTool('add_item', {
        'name': '测试羽毛球拍',
        'price': 50,
        'quantity': 2,
        'category_name': '运动户外',
        'space_name': '厨房',
        'purchase_date': '2026-11-01',
        'tags': ['运动'],
      });
      expect(result, contains('录入成功'));
      final item = store.items.first;
      expect(item.name, '测试羽毛球拍');
      expect(item.price, 50);
      expect(item.quantity, 2);
      expect(item.categoryId, 'cat-sport');
      expect(item.spaceId, 'sp-kitchen');
      expect(item.purchaseDate, '2026-11-01');
    });

    test('add_item 缺名称返回错误提示', () async {
      await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      final result = svc.executeTool('add_item', {'price': 50});
      expect(result, contains('缺少物品名称'));
    });

    test('add_item 空间模糊匹配', () async {
      final store = await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      svc.executeTool('add_item', {'name': '模糊匹配测试', 'space_name': '书'});
      // 候选按种子顺序：书房最先包含「书」
      expect(store.items.first.spaceId, 'sp-study');
    });

    test('query_items count_by_month', () async {
      await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      final result = svc.executeTool('query_items', {'intent': 'count_by_month'});
      expect(result, contains('录入'));
      expect(result, contains('2026-11'));
    });

    test('query_items recent_list 与未知类型', () async {
      await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      expect(svc.executeTool('query_items', {'intent': 'recent_list'}), contains('最近添加'));
      expect(svc.executeTool('query_items', {'intent': 'unknown'}), contains('未知查询类型'));
    });

  });

  group('搜索历史', () {
    test('去重置顶与上限 10 条', () async {
      final store = await _freshStore();
      for (final q in ['a', 'b', 'c', 'a']) {
        store.addSearchHistory(q);
      }
      expect(store.searchHistory(), ['a', 'c', 'b']);
      for (var i = 0; i < 12; i++) {
        store.addSearchHistory('k$i');
      }
      expect(store.searchHistory().length, 10);
      expect(store.searchHistory().first, 'k11');
      store.clearSearchHistory();
      expect(store.searchHistory(), isEmpty);
    });
  });


  group('AI 请求体序列化', () {
    test('send 请求体可解析且 messages 均为对象（回归 ChatTurn 泄漏）', () async {
      await _freshStore();
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '好的，已记录羽毛球拍'},
                'finish_reason': 'stop',
              }
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final svc = GlmChatService(apiKey: 'test', client: client);
      final reply = await svc.send('今天买羽毛球拍花了50块', ownerName: '我');
      expect(reply, '好的，已记录羽毛球拍');

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages, isNotEmpty);
      for (final m in messages) {
        expect(m, isA<Map<String, dynamic>>(), reason: 'ChatTurn 实例泄漏到了请求体');
        expect((m as Map)['role'], isNotNull);
      }
      // system 轮恰好一次且在首位
      expect((messages.first as Map)['role'], 'system');
      expect(messages.where((m) => (m as Map)['role'] == 'system').length, 1);
      // 用户消息在末尾
      expect((messages.last as Map)['role'], 'user');
    });

    test('开启快速回答时请求体带 thinking.disabled', () async {
      await _freshStore();
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': 'ok'}, 'finish_reason': 'stop'},
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final svc = GlmChatService(apiKey: 'test', quickAnswer: true, client: client);
      await svc.send('在吗', ownerName: '我');
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect((body['thinking'] as Map)['type'], 'disabled');
    });

    test('sendStreaming 解析 reasoning_content 思考过程与正文增量', () async {
      await _freshStore();
      final sseLines = [
        'data: {"choices":[{"delta":{"reasoning_content":"正在想"}}]}',
        'data: {"choices":[{"delta":{"content":"你好"}}]}',
        'data: {"choices":[{"delta":{"content":"呀"}}]}',
        'data: [DONE]',
      ];
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(sseLines.map((s) => utf8.encode('$s\n\n'))),
          200,
        );
      });
      final svc = GlmChatService(apiKey: 'test', client: client);
      final thoughts = <String>[];
      final deltas = <String>[];
      final reply = await svc.sendStreaming(
        '在吗',
        ownerName: '我',
        onDelta: deltas.add,
        onThinking: thoughts.add,
      );
      expect(reply, '你好呀');
      expect(thoughts.single, '正在想');
      expect(deltas.last, '你好呀');
    });

    test('executeTool add_item 回调新建物品（供页面即时出卡片）', () async {
      final store = await _freshStore();
      final svc = GlmChatService(apiKey: 'test');
      Item? created;
      svc.executeTool('add_item', {'name': '回调测试', 'price': 9.9}, onToolEvent: (name, item) {
        expect(name, 'add_item');
        created = item;
      });
      expect(created, isNotNull);
      expect(created!.name, '回调测试');
      expect(store.items.first.id, created!.id);
    });
  });

  group('AI 页与首启引导', () {
    testWidgets('AI 页未配置 key 显示引导卡', (tester) async {
      await _freshStore();
      await tester.pumpWidget(
        MaterialApp(theme: buildGuiwuTheme(), home: const AiChatPage()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('对话式录入物品'), findsOneWidget);
      expect(find.text('去设置页配置 API Key'), findsOneWidget);
    });

    testWidgets('首次启动弹出三选一引导', (tester) async {
      final store = await _freshStore();
      await tester.pumpWidget(
        MaterialApp(theme: buildGuiwuTheme(), home: HomeShell(store: store)),
      );
      await tester.pumpAndSettle();
      expect(find.text('欢迎使用物盒册'), findsOneWidget);
      expect(find.text('载入示例数据'), findsOneWidget);
      expect(find.text('从 Web 版导入'), findsOneWidget);
      expect(find.text('空白开始'), findsOneWidget);
    });
  });
}
