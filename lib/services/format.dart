/// 展示格式化工具（对应 Web 版 utils.js 的 money / bytesText / parseTags）
library;

String _group(String digits) {
  final b = StringBuffer();
  final n = digits.length;
  for (var i = 0; i < n; i++) {
    b.write(digits[i]);
    final rest = n - i - 1;
    if (rest > 0 && rest % 3 == 0) b.write(',');
  }
  return b.toString();
}

/// 金额显示：¥1,299（与 Web 版一致：整数 + 千分位 + ¥ 前缀）
String money(num n, {bool withSymbol = true}) {
  final rounded = n.round();
  final text = _group(rounded.abs().toString());
  final signed = rounded < 0 ? '-$text' : text;
  return withSymbol ? '¥$signed' : signed;
}

/// 字节数 → 可读文本
String bytesText(int bytes) {
  if (bytes <= 0) return '0 KB';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

/// 解析标签输入（逗号/顿号/空格分隔，去重，最多 8 个）
List<String> parseTags(String text) {
  return text
      .split(RegExp(r'[,，、;；\s]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .take(8)
      .toSet()
      .toList();
}
