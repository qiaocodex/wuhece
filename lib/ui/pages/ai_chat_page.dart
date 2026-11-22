/// AI 助手：自然语言对话录入物品 / 查询统计（智谱 GLM）
library;

import 'package:material_ui/material_ui.dart';

import '../../services/glm_chat.dart';
import '../../store/app_store.dart';
import '../theme.dart';
import '../widgets.dart';
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

  AppStore get store => AppStore.instance;

  bool get _hasKey => (store.settings.aiApiKey ?? '').isNotEmpty;

  GlmChatService get _chat {
    return _service ??= GlmChatService(
      apiKey: store.settings.aiApiKey ?? '',
      model: store.settings.aiModel,
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
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

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending || !_hasKey) return;
    _inputCtrl.clear();
    setState(() {
      _items.add(_Bubble.user(text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      await _chat.sendStreaming(
        text,
        ownerName: store.settings.owner,
        onDelta: (partial) {
          setState(() {
            if (_items.isNotEmpty) {
              _items[_items.length - 1] = _Bubble.assistant(partial);
            }
          });
          _scrollToBottom();
        },
      );
    } on GlmException catch (err) {
      setState(() {
        if (_items.isNotEmpty) {
          _items[_items.length - 1] = _Bubble.assistant('⚠️ ${err.message}', isError: true);
        }
      });
    } catch (err) {
      setState(() {
        if (_items.isNotEmpty) {
          _items[_items.length - 1] = _Bubble.assistant('⚠️ 出错了：$err', isError: true);
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

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
    return Column(
      children: [
        Expanded(
          child: _items.isEmpty && !_sending
              ? _emptyHint()
              : ListView.builder(
                  controller: _listCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: _items.length + (_sending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_sending && i == _items.length) {
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

  Widget _typingRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(context.gc.primary)),
          ),
          const SizedBox(width: 10),
          Text(
            '正在思考 / 执行录入…',
            style: TextStyle(fontSize: 12, color: context.gc.muted),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Bubble bubble) {
    final isUser = bubble.isUser;
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

class _Bubble {
  _Bubble.user(this.text)
      : isUser = true,
        isError = false;
  _Bubble.assistant(this.text, {this.isError = false})
      : isUser = false;

  final String text;
  final bool isUser;
  final bool isError;
}
