/// 智谱 GLM 对话服务：AI 对话录入物品 / 查询统计
///
/// 走 OpenAI 兼容协议（https://open.bigmodel.cn/api/paas/v4/chat/completions），
/// glm-4.5-flash 免费且原生支持 function calling。
/// 模型通过 [tools] 调用本地能力：add_item 直接写入数据层、query_items
/// 反查本地数据（如"这个月录入了多少物品"），上下文记忆保留最近 12 条消息。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../store/app_store.dart';
import 'dates.dart';
import 'format.dart';

/// GLM 调用异常（message 已是友好中文，可直接展示）
class GlmException implements Exception {
  GlmException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 一轮会话消息（线格式，直接对应 GLM 请求体）
class ChatTurn {
  ChatTurn(this.data);
  ChatTurn.user(String content)
      : data = {'role': 'user', 'content': content};
  ChatTurn.assistant(String content)
      : data = {'role': 'assistant', 'content': content};

  final Map<String, dynamic> data;

  String get role => data['role'] as String? ?? '';
  String get text => data['content']?.toString() ?? '';

  /// UI 展示用：assistant 的 tool_calls 轮显示占位文本
  bool get isToolRound => data.containsKey('tool_calls');
}

class GlmChatService {
  GlmChatService({required this.apiKey, this.model = defaultModel, http.Client? client})
      : _client = client ?? http.Client();

  late final http.Client _client;

  static const endpoint = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const defaultModel = 'glm-4.5-flash';

  /// 常用免费/低价模型（设置页下拉）
  static const knownModels = ['glm-4.5-flash', 'glm-4.5-air', 'glm-4-flash'];

  final String apiKey;
  final String model;

  /// 会话历史（不含 system；线格式）
  final List<ChatTurn> history = [];
  static const int _maxHistoryTurns = 12;

  /// 探测 key 是否可用（设置页「测试连接」）
  Future<void> probe() async {
    final data = await _post(jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': '回复「连接成功」四个字'},
      ],
      'max_tokens': 16,
    }));
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw GlmException('接口返回异常，请检查模型名称是否正确');
    }
  }

  /// 发送一条用户消息；自动执行模型发起的本地工具（最多 3 轮），
  /// 返回 assistant 的最终回复文本。
  Future<String> send(String userText, {required String ownerName}) async {
    if (history.where((t) => t.role == 'user').isEmpty) {
      history.insert(0, _systemTurn(ownerName));
    }
    history.add(ChatTurn.user(userText));
    _trimHistory();

    for (var round = 0; round < 3; round++) {
      final data = await _post(jsonEncode({
        'model': model,
        // history[0] 已含 system 轮（首次发送时插入），全部取线格式数据
        'messages': [...history.map((t) => t.data)],
        'tools': _tools,
        'temperature': 0.3,
      }));

      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw GlmException('接口返回异常，请稍后重试');
      }
      final message = (choices.first as Map)['message'] as Map<String, dynamic>;
      final toolCalls = message['tool_calls'] as List?;

      if (toolCalls == null || toolCalls.isEmpty) {
        final reply = message['content']?.toString() ?? '';
        history.add(ChatTurn.assistant(reply));
        _trimHistory();
        return reply.isEmpty ? '（模型未返回内容）' : reply;
      }

      // 执行本地工具并回传结果
      history.add(ChatTurn(message));
      final toolResults = <Map<String, dynamic>>[];
      for (final call in toolCalls) {
        final c = call as Map<String, dynamic>;
        final fn = (c['function'] ?? {}) as Map<String, dynamic>;
        final name = fn['name']?.toString() ?? '';
        final args = _parseArgs(fn['arguments']);
        final result = executeTool(name, args);
        toolResults.add({
          'role': 'tool',
          'tool_call_id': c['id'],
          'content': result,
        });
      }
      history.addAll(toolResults.map(ChatTurn.new));
      _trimHistory();
    }
    return '（本轮工具调用次数过多，已中断，请换个说法重试）';
  }

  /// 流式发送：通过 SSE 增量回调 assistant 部分文本，
  /// 工具调用轮自动执行并继续生成，返回最终完整回复。
  Future<String> sendStreaming(
    String userText, {
    required String ownerName,
    required void Function(String partialText) onDelta,
  }) async {
    if (history.where((t) => t.role == 'user').isEmpty) {
      history.insert(0, _systemTurn(ownerName));
    }
    history.add(ChatTurn.user(userText));
    _trimHistory();

    for (var round = 0; round < 3; round++) {
      final request = http.Request('POST', Uri.parse(endpoint))
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'model': model,
          // history[0] 已含 system 轮（首次发送时插入），全部取线格式数据
          'messages': [...history.map((t) => t.data)],
          'tools': _tools,
          'temperature': 0.3,
          'stream': true,
        });

      http.StreamedResponse response;
      try {
        response = await _client.send(request).timeout(const Duration(seconds: 120));
      } on TimeoutException {
        throw GlmException('请求超时，请检查网络后重试');
      } catch (err) {
        throw GlmException('网络连接失败，请检查网络后重试');
      }
      if (response.statusCode == 401) {
        throw GlmException('API Key 无效或已过期，请到「设置 → AI 助手」检查');
      }
      if (response.statusCode != 200) {
        final bodyText = await response.stream.bytesToString();
        final snippet = bodyText.length > 160 ? '${bodyText.substring(0, 160)}…' : bodyText;
        throw GlmException('接口错误 ${response.statusCode}：$snippet');
      }

      // SSE 解析：累积文本增量与工具调用片段
      var contentBuf = '';
      final toolCalls = <int, Map<String, dynamic>>{};

      await for (final raw in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final line = raw.trim();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        if (payload.isEmpty) continue;

        Map<String, dynamic> chunk;
        try {
          chunk = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = chunk['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'];
        if (delta == null) continue;

        final contentDelta = delta['content'];
        if (contentDelta != null && contentDelta.toString().isNotEmpty) {
          contentBuf += contentDelta.toString();
          onDelta(contentBuf);
        }
        for (final tc in (delta['tool_calls'] as List? ?? const [])) {
          final tcm = tc as Map;
          final idx = (tcm['index'] as num?)?.toInt() ?? 0;
          final cur = toolCalls.putIfAbsent(idx, () => <String, dynamic>{
                'id': 'call_$idx',
                'function': {'name': '', 'arguments': ''},
              });
          if (tcm['id'] != null) cur['id'] = tcm['id'];
          final fn = (tcm['function'] ?? {}) as Map;
          if (fn['name'] != null && fn['name'].toString().isNotEmpty) {
            cur['function']['name'] = fn['name'].toString();
          }
          if (fn['arguments'] != null) {
            cur['function']['arguments'] =
                cur['function']['arguments'].toString() + fn['arguments'].toString();
          }
        }
      }

      if (toolCalls.isNotEmpty) {
        history.add(ChatTurn({
          'role': 'assistant',
          if (contentBuf.isNotEmpty) 'content': contentBuf,
          'tool_calls': [
            for (final entry in toolCalls.entries)
              {
                'id': entry.value['id'],
                'type': 'function',
                'function': entry.value['function'],
              }
          ],
        }));
        for (final entry in toolCalls.entries) {
          final fn = entry.value['function'] as Map<String, dynamic>;
          final result = executeTool(fn['name']?.toString() ?? '', _parseArgs(fn['arguments']));
          history.add(ChatTurn({
            'role': 'tool',
            'tool_call_id': entry.value['id'],
            'content': result,
          }));
        }
        _trimHistory();
        continue;
      }

      final reply = contentBuf.isEmpty ? '（模型未返回内容）' : contentBuf;
      history.add(ChatTurn.assistant(reply));
      _trimHistory();
      return reply;
    }
    return '（本轮工具调用次数过多，已中断，请换个说法重试）';
  }

  /// 清空会话记忆
  void clear() => history.clear();

  /* ------------------------- 内部实现 ------------------------- */

  ChatTurn _systemTurn(String ownerName) {
    return ChatTurn({
      'role': 'system',
      'content': '你是「物盒册」应用内的物品录入助手，用户是$ownerName。'
          '今天是 ${toISODate()}（格式 yyyy-MM-dd）。'
          '用户会用口语描述买/卖了什么物品、查询录入情况，你需要：'
          '1) 录入或修改物品时调用 add_item 工具（不要自己编造工具参数以外的信息，缺省字段就缺省）；'
          '2) 统计或查询时调用 query_items 工具；'
          '3) 工具返回结果后，用简短口语化的中文回复，不要输出 JSON 或表格。'
          '如果用户只是闲聊，直接简短回复即可。',
    });
  }

  void _trimHistory() {
    // 始终保留最前面的 system 轮，其余按数量裁剪
    final systemFirst = history.isNotEmpty && history.first.role == 'system';
    final rest = systemFirst ? history.sublist(1) : history;
    if (rest.length > _maxHistoryTurns) {
      final overflow = rest.length - _maxHistoryTurns;
      rest.removeRange(0, overflow);
    }
  }

  static Map<String, dynamic> _parseArgs(Object? arguments) {
    if (arguments == null) return {};
    if (arguments is Map) return Map<String, dynamic>.from(arguments);
    try {
      final decoded = jsonDecode(arguments.toString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _post(String body) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw GlmException('请求超时，请检查网络后重试');
    } catch (err) {
      throw GlmException('网络连接失败：$err');
    }

    if (response.statusCode == 401) {
      throw GlmException('API Key 无效或已过期，请到「设置 → AI 助手」检查');
    }
    if (response.statusCode != 200) {
      final snippet = response.body.length > 160
          ? '${response.body.substring(0, 160)}…'
          : response.body;
      throw GlmException('接口错误 ${response.statusCode}：$snippet');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw GlmException('接口返回内容无法解析');
    }
  }

  /* ------------------------- 本地工具 ------------------------- */

  /// 工具 schema（OpenAI 兼容格式）
  List<Map<String, dynamic>> get _tools => [
        {
          'type': 'function',
          'function': {
            'name': 'add_item',
            'description': '录入或更新一件物品到物品库。价格单位为元；'
                'purchase_date 格式 yyyy-MM-dd；不确定的字段不要填，不要编造。',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'description': '物品名称，必填'},
                'category_name': {'type': 'string', 'description': '分类名，如 数码电子/厨房用品，不确定可不填'},
                'space_name': {'type': 'string', 'description': '存放位置名，如 卧室/书架，不确定可不填'},
                'quantity': {'type': 'integer', 'description': '数量，默认 1'},
                'price': {'type': 'number', 'description': '单价（元）'},
                'purchase_date': {'type': 'string', 'description': '购入日期 yyyy-MM-dd，默认今天'},
                'warranty_months': {'type': 'integer', 'description': '保修期（月）'},
                'tags': {'type': 'array', 'items': {'type': 'string'}, 'description': '标签'},
                'note': {'type': 'string', 'description': '备注'},
              },
              'required': ['name'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'query_items',
            'description': '查询物品库统计或清单。查"这个月录入多少"用 intent=count_by_month。',
            'parameters': {
              'type': 'object',
              'properties': {
                'intent': {
                  'type': 'string',
                  'enum': ['count_by_month', 'recent_list', 'count_status', 'count_by_category'],
                  'description': '查询类型：按月统计录入数 / 最近录入清单 / 各状态数量 / 各分类数量',
                },
                'month': {'type': 'string', 'description': 'yyyy-MM，intent=count_by_month 时使用，默认当月'},
                'limit': {'type': 'integer', 'description': '清单条数上限，默认 5'},
              },
              'required': ['intent'],
            },
          },
        },
      ];

  /// 执行本地工具并返回给模型的结果文本（公开以便单测）
  String executeTool(String name, Map<String, dynamic> args) {
    try {
      switch (name) {
        case 'add_item':
          return _toolAddItem(args);
        case 'query_items':
          return _toolQueryItems(args);
        default:
          return '错误：未知工具 $name';
      }
    } catch (err) {
      return '工具执行失败：$err';
    }
  }

  String _toolAddItem(Map<String, dynamic> args) {
    final store = _store;
    final name = (args['name'] ?? '').toString().trim();
    if (name.isEmpty) return '错误：缺少物品名称，无法录入。请向用户询问物品名称。';

    // 分类：按名查找，不存在则创建
    final categoryName = (args['category_name'] ?? '').toString().trim();
    final categoryId = categoryName.isNotEmpty
        ? (store.ensureCategory(categoryName) ?? _fallbackCategoryId(store))
        : _fallbackCategoryId(store);

    // 空间：精确匹配 → 包含匹配
    final spaceName = (args['space_name'] ?? '').toString().trim();
    String? spaceId;
    if (spaceName.isNotEmpty) {
      for (final s in store.spaces) {
        if (s.name == spaceName) {
          spaceId = s.id;
          break;
        }
      }
      spaceId ??= store
          .spaces
          .where((s) => s.name.contains(spaceName))
          .map((s) => s.id)
          .firstOrNull;
    }

    final quantity = (args['quantity'] as num?)?.toInt() ?? 1;
    final price = (args['price'] as num?)?.toDouble() ?? 0;
    final rawDate = (args['purchase_date'] ?? '').toString().trim();
    final purchaseDate = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) ? rawDate : toISODate();
    final warrantyMonths = (args['warranty_months'] as num?)?.toInt() ?? 0;
    final tags = (args['tags'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
    final note = (args['note'] ?? '').toString();

    final item = store.addItem(
      name: name,
      categoryId: categoryId,
      spaceId: spaceId,
      quantity: quantity,
      price: price,
      purchaseDate: purchaseDate,
      warrantyMonths: warrantyMonths,
      tags: tags,
      note: note,
    );

    final categoryLabel = store.getCategory(item.categoryId)?.name ?? '未分类';
    final spaceLabel = store.spacePathLabel(item.spaceId);
    final valuePart = item.price > 0 ? '，价值 ${money(item.value)}' : '';
    return '录入成功：${item.name}（分类 $categoryLabel，'
        '数量 ${item.quantity}$valuePart，'
        '购入 ${item.purchaseDate}，位置：$spaceLabel）';
  }

  String _fallbackCategoryId(AppStore store) =>
      store.categories.isNotEmpty ? store.categories.first.id : 'cat-other';

  AppStore get _store => AppStore.instance;

  String _toolQueryItems(Map<String, dynamic> args) {
    final store = _store;
    final intent = (args['intent'] ?? 'count_by_month').toString();
    switch (intent) {
      case 'count_by_month':
        final month = (args['month'] ?? toISODate().substring(0, 7)).toString();
        final count = store.items.where((it) => it.createdAt.length >= 7 && it.createdAt.substring(0, 7) == month).length;
        return '$month 录入 $count 条物品记录（当前物品库共 ${store.items.length} 条）';
      case 'recent_list':
        final limit = (args['limit'] as num?)?.toInt() ?? 5;
        final rows = store.recentItems(limit < 1 ? 5 : limit)
            .map((it) => '${it.name}（${money(it.price)}，${store.spacePathLabel(it.spaceId)}）')
            .join('、');
        return rows.isEmpty ? '物品库还是空的' : '最近添加：$rows';
      case 'count_status':
        final rows = store.statusStats().where((s) => s.count > 0).map((s) => '${s.label} ${s.count} 件').join('，');
        return rows.isEmpty ? '物品库还是空的' : '各状态：$rows';
      case 'count_by_category':
        final rows = store.categoryStats().where((c) => c.count > 0).map((c) => '${c.category.name} ${c.count} 条').join('，');
        return rows.isEmpty ? '物品库还是空的' : '各分类：$rows';
      default:
        return '未知查询类型 $intent';
    }
  }
}
