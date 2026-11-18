/// 唯一 ID 生成（对应 Web 版 utils.js 的 uid）
library;

import 'dart:math';

int _seq = 0;
final Random _random = Random();

String uid(String prefix) {
  _seq += 1;
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = _random.nextInt(0x7FFFFFFF).toRadixString(36);
  return '${prefix}_${ts}_$_seq$rand';
}
