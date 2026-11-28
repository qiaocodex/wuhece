/// AI 助手：自然语言对话录入物品 / 查询统计（智谱 GLM）
///
/// 常见录入说法（如「买了体脂秤39.9」）走本地模板快路径（quick_entry.dart）
/// 毫秒级落库；其余消息走 AI 流式对话，正文按打字机节奏逐字呈现，
/// 深度思考过程实时显示预览，AI 录入成功时展示可撤销/修改的结构化卡片。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../services/dates.dart';
import '../../services/format.dart';
import '../../services/glm_chat.dart';
import '../../services/quick_entry.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_form.dart';
import 'settings_page.dart';

/// 打开 AI 助手（push 路由）
Future<void> openAiChat(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const AiChatPage()),
  );
}

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  GlmChatService? _service;
  final _items = <_Bubble>[]; // 展示用气泡
  final _inputCtrl = TextEditingController();
  final _listCtrl = ScrollController();
  bool _sending = false;

  /// 正在流式输出的文本气泡下标（null = 尚无可显示正文，打字行兜底）
  int? _streamingIndex;

  /// 深度思考过程预览（SSE reasoning_content 的累积尾部）
  String _thinkingPreview = '';

  late final _Typewriter _typewriter = _Typewriter(_onTyped);

  /// 自动滚动节流
  DateTime _lastScrollAt = DateTime.fromMillisecondsSinceEpoch(0);

  AppStore get store => AppStore.instance;

  bool get _hasKey => (store.settings.aiApiKey ?? '').isNotEmpty;

  GlmChatService get _chat {
    return _service ??= GlmChatService(
      apiKey: store.settings.aiApiKey ?? '',
      model: store.settings.aiModel,
      quickAnswer: store.settings.aiQuickAnswer,
    );
  }

  @override
  void dispose() {
    _typewriter.dispose();
    _inputCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastScrollAt).inMilliseconds < 400) return;
    _lastScrollAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listCtrl.hasClients) {
        _listCtrl.animateTo(
          _listCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /* ------------------------- 发送 ------------------------- */

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending || !_hasKey) return;
    _inputCtrl.clear();

    // 1) 本地模板快路径：常见录入句式直接落库，不等 AI（毫秒级）
    final quick = tryQuickEntry(text, store);
    if (quick != null) {
      final item = applyEntryToStore(
        store,
        name: quick.name,
        price: quick.price,
        quantity: quick.quantity,
        purchaseDate: quick.purchaseDate,
        warrantyMonths: quick.warrantyMonths,
        categoryName: quick.categoryName,
        spaceName: quick.spaceName,
      );
      setState(() {
        _items.add(_Bubble.user(text));
        _items.add(_Bubble.entry(item.id));
      });
      _scrollToBottom(force: true);
      return;
    }

    // 2) AI 对话：流式 + 打字机 + 思考预览
    setState(() {
      _items.add(_Bubble.user(text));
      _sending = true;
      _streamingIndex = null;
      _thinkingPreview = '';
    });
    _scrollToBottom(force: true);

    try {
      await _chat.sendStreaming(
        text,
        ownerName: store.settings.owner,
        onDelta: _typewriter.say,
        onThinking: (thought) {
          if (!mounted) return;
          setState(() => _thinkingPreview = thought);
        },
        onTool: (toolName, createdItem) {
          if (!mounted) return;
          setState(() {
            _typewriter.finish();
            _typewriter.reset();
            // 工具轮结束后正文另起新气泡（成功卡片插在中间）
            _streamingIndex = null;
            if (createdItem != null) {
              _items.add(_Bubble.entry(createdItem.id));
            }
          });
          _scrollToBottom(force: true);
        },
      );
    } on GlmException catch (err) {
      _typewriter.finish();
      setState(() => _items.add(_Bubble.assistant('⚠️ ${err.message}', isError: true)));
    } catch (err) {
      _typewriter.finish();
      setState(() => _items.add(_Bubble.assistant('⚠️ 出错了：$err', isError: true)));
    } finally {
      _typewriter.finish();
      if (mounted) {
        setState(() {
          _sending = false;
          _streamingIndex = null;
          _thinkingPreview = '';
        });
      }
      _scrollToBottom(force: true);
    }
  }

  /// 打字机每次释放字符时刷新流式气泡
  void _onTyped(String shown) {
    if (!mounted) return;
    setState(() {
      if (_streamingIndex == null) {
        _items.add(_Bubble.assistant(shown));
        _streamingIndex = _items.length - 1;
      } else {
        _items[_streamingIndex!].text = shown;
      }
    });
    _scrollToBottom();
  }

  /* ------------------------- 成功卡片操作 ------------------------- */

  void _undoEntry(_Bubble bubble) {
    final id = bubble.entryId;
    if (id == null) return;
    store.deleteItem(id);
    setState(() => bubble.undone = true);
  }

  Future<void> _editEntry(_Bubble bubble) async {
    final item = bubble.entryId == null ? null : store.getItem(bubble.entryId!);
    if (item == null) return;
    await openItemForm(context, item);
    if (mounted) setState(() {}); // 表单保存后刷新卡片
  }

  /* ------------------------- 页面框架 ------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gc.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.gc.bg,
        surfaceTintColor: context.gc.bg,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('AI 助手', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.gc.ink)),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt, size: 19),
            tooltip: '清空会话',
            onPressed: _items.isEmpty
                ? null
                : () {
                    setState(() {
                      _items.clear();
                      _streamingIndex = null;
                      _thinkingPreview = '';
                      _chat.clear();
                    });
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _hasKey ? _chatBody() : _guideBody(),
      ),
    );
  }

  /* ------------------------- 未配置 key ------------------------- */

  Widget _guideBody() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.gc.primaryWeak,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.smart_toy_outlined, size: 30, color: context.gc.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  '对话式录入物品',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.gc.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  '用一句话描述，AI 帮你完成录入：\n'
                  '「今天买羽毛球拍花了 50 块，录一下」\n\n'
                  '这类常见说法不需要等待 AI，本地直接秒录；\n'
                  '也可以直接问：\n'
                  '「这个月录入了多少物品」\n\n'
                  '底层基于智谱 GLM-4.5-flash（免费模型），'
                  '需要在设置里填入你自己的 API Key，'
                  'Key 仅保存在本机。',
                  style: TextStyle(fontSize: 12.5, color: context.gc.inkSoft, height: 1.8),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                    );
                  },
                  icon: const Icon(Icons.settings_outlined, size: 15),
                  label: const Text('去设置页配置 API Key'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /* ------------------------- 对话 ------------------------- */

  Widget _chatBody() {
    final showTyping = _sending && _streamingIndex == null;
    return Column(
      children: [
        Expanded(
          child: _items.isEmpty && !showTyping
              ? _emptyHint()
              : ListView.builder(
                  controller: _listCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: _items.length + (showTyping ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (showTyping && i == _items.length) {
                      return _typingRow();
                    }
                    return _bubble(_items[i]);
                  },
                ),
        ),
        const Divider(height: 1),
        _inputBar(),
      ],
    );
  }

  Widget _emptyHint() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              '试一试',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.gc.muted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            _exampleCard('「今天买羽毛球拍花了 50 块，录入一下」'),
            const SizedBox(height: 8),
            _exampleCard('「MacBook Air 是什么时候买的，还在保修期吗」'),
            const SizedBox(height: 8),
            _exampleCard('「这个月录入了多少物品」'),
            const SizedBox(height: 8),
            _exampleCard('「家里现在还有哪些东西是闲置的」'),
          ],
        ),
      ),
    );
  }

  Widget _exampleCard(String text) {
    return InkWell(
      onTap: () {
        _inputCtrl.text = text;
        _send();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.gc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.gc.line),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: context.gc.inkSoft),
        ),
      ),
    );
  }

  /// 「正在思考」打字行：无正文可显示时兜底，附思考过程预览
  Widget _typingRow() {
    final preview = _thinkingPreview.replaceAll(RegExp(r'\s+'), ' ').trim();
    final tail = preview.length > 80 ? '…${preview.substring(preview.length - 80)}' : preview;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(context.gc.primary)),
                ),
                const SizedBox(width: 10),
                Text(
                  preview.isEmpty ? '正在思考 / 执行录入…' : '正在思考…',
                  style: TextStyle(fontSize: 12, color: context.gc.muted),
                ),
              ],
            ),
            if (tail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                tail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.5, color: context.gc.muted, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Bubble bubble) {
    return switch (bubble.kind) {
      _BubbleKind.entry => _entryCard(bubble),
      _ => _textBubble(bubble),
    };
  }

  Widget _textBubble(_Bubble bubble) {
    final isUser = bubble.kind == _BubbleKind.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? context.gc.primary : context.gc.surface,
          borderRadius: BorderRadius.circular(14).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
          border: isUser ? null : Border.all(color: context.gc.line),
        ),
        child: SelectableText(
          bubble.text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.6,
            color: isUser ? Colors.white : (bubble.isError ? context.gc.danger : context.gc.ink),
          ),
        ),
      ),
    );
  }

  /// AI 录入成功卡片（本地快路径与 AI 工具录入共用）
  Widget _entryCard(_Bubble bubble) {
    final item = bubble.entryId == null ? null : store.getItem(bubble.entryId!);
    final gone = item == null || bubble.undone;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        decoration: BoxDecoration(
          color: context.gc.surface,
          borderRadius: BorderRadius.circular(14).copyWith(bottomLeft: const Radius.circular(4)),
          border: Border.all(color: context.gc.line),
        ),
        child: gone
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.undo_rounded, size: 15, color: context.gc.muted),
                  const SizedBox(width: 8),
                  Text('已撤销', style: TextStyle(fontSize: 12.5, color: context.gc.muted)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 17, color: context.gc.primary),
                      const SizedBox(width: 6),
                      Text('录入成功', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.gc.ink)),
                      const Spacer(),
                      Text(formatDate(item.purchaseDate), style: TextStyle(fontSize: 11.5, color: context.gc.muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, thickness: 0.6, color: context.gc.line),
                  const SizedBox(height: 6),
                  _entryRow('名称', item.name),
                  if (item.price > 0)
                    _entryRow('价格', '${money(item.price)}${item.quantity > 1 ? ' × ${item.quantity}' : ''}'),
                  _entryRow('分类', store.getCategory(item.categoryId)?.name ?? '未分类'),
                  _entryRow('位置', store.spacePathLabel(item.spaceId)),
                  if (item.warrantyMonths > 0) _entryRow('保修', '${item.warrantyMonths} 个月'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _undoEntry(bubble),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: context.gc.muted,
                        ),
                        child: const Text('撤销'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => _editEntry(bubble),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: context.gc.primary,
                        ),
                        child: const Text('修改'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _entryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(label, style: TextStyle(fontSize: 12.5, color: context.gc.muted)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, color: context.gc.ink)),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom * 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '例如：昨天买了个保温杯 99 块，放厨房',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _sending
                  ? const SizedBox(
                      width: 38,
                      height: 38,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send, size: 18),
                      tooltip: '发送',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BubbleKind { user, text, entry }

class _Bubble {
  _Bubble.user(this.text)
      : kind = _BubbleKind.user,
        isError = false;
  _Bubble.assistant(this.text, {this.isError = false})
      : kind = _BubbleKind.text;
  _Bubble.entry(this.entryId)
      : kind = _BubbleKind.entry,
        text = '',
        isError = false;

  _BubbleKind kind;
  String text; // 打字机流式期间会被持续改写
  bool isError;
  String? entryId; // 录入成功卡片关联的物品 id
  bool undone = false;
}

/// 打字机节奏控制器：流式增量按逐字节奏刷出，积压越多释放越快
class _Typewriter {
  _Typewriter(this._flush);

  final void Function(String text) _flush;
  Timer? _timer;
  String _target = '';
  int _shown = 0;

  void say(String full) {
    _target = full;
    _timer ??= Timer.periodic(const Duration(milliseconds: 30), _tick);
  }

  void _tick(Timer _) {
    final backlog = _target.length - _shown;
    if (backlog <= 0) return;
    final step = backlog > 160 ? 12 : backlog > 60 ? 6 : backlog > 24 ? 3 : 1;
    _shown = (_shown + step).clamp(0, _target.length);
    _flush(_target.substring(0, _shown));
  }

  /// 立即显示全部剩余文本（不重置进度）
  void finish() {
    _timer?.cancel();
    _timer = null;
    if (_shown < _target.length) {
      _shown = _target.length;
      _flush(_target);
    }
  }

  /// 清空进度（新一轮内容从零开始逐字出）
  void reset() {
    _timer?.cancel();
    _timer = null;
    _target = '';
    _shown = 0;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
