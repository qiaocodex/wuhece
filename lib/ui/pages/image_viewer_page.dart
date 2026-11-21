/// 全屏图片查看器：左右翻页 + 双指缩放 + 底部信息条
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/dates.dart';
import '../../services/format.dart';
import '../../store/app_store.dart';

/// 打开图片查看器（items 为带图片的物品列表）
Future<void> openImageViewer(BuildContext context, List<Item> items, int initialIndex) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ImageViewerPage(items: items, initialIndex: initialIndex),
    ),
  );
}

Uint8List? _decode(String src) {
  try {
    final i = src.indexOf('base64,');
    return i >= 0 ? base64Decode(src.substring(i + 7)) : base64Decode(src);
  } catch (_) {
    return null;
  }
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.items, required this.initialIndex});

  final List<Item> items;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pageCtrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              final bytes = _decode(item.image ?? '');
              if (bytes == null) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38),
                );
              }
              return InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              );
            },
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 22, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                Text(
                  '${_index + 1} / ${widget.items.length}',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                color: Colors.black54,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.items[_index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${store.spacePathLabel(widget.items[_index].spaceId)} · ${money(widget.items[_index].value)}'
                      ' · 购入 ${formatDate(widget.items[_index].purchaseDate)}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
