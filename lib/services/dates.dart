/// 日期工具（保持与 Web 版 utils.js 相同的字符串格式，便于备份互通）
library;

import 'dart:math';

String _p2(int n) => n.toString().padLeft(2, '0');

/// 本地日期 → `yyyy-MM-dd`
String toISODate([DateTime? date]) {
  final d = date ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}';
}

/// n 天前的 `yyyy-MM-dd`
String dateDaysAgo(int n) => toISODate(DateTime.now().subtract(Duration(days: n)));

/// n 天前本地 10:24 → UTC ISO 字符串（带 Z，与 Web 版 toISOString 一致）
String isoDaysAgo(int n) {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day - n, 10, 24);
  return d.toUtc().toIso8601String();
}

/// 当前 UTC ISO 字符串（带 Z）
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// `2024/03/05`（不足时原样返回）
String formatDate(String? value) {
  if (value == null || value.isEmpty) return '—';
  final raw = value.length >= 10 ? value.substring(0, 10) : value;
  final parts = raw.split('-');
  if (parts.length != 3) return raw;
  return '${parts[0]}/${parts[1]}/${parts[2]}';
}

/// `2024/03/05 10:24`
String formatDateTime(String? value) {
  if (value == null || value.isEmpty) return '—';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return '${d.year}/${_p2(d.month)}/${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
}

/// 距今天数（无法解析时返回 null）
int? daysSince(String? value) {
  if (value == null || value.isEmpty) return null;
  final then = DateTime.tryParse(value);
  if (then == null) return null;
  final diff = DateTime.now().difference(then).inMilliseconds;
  return max(0, diff ~/ 86400000);
}

/// ISO 日期加 N 个月（用于保修截止日）
String? addMonths(String? isoDate, int months) {
  if (isoDate == null || isoDate.isEmpty) return null;
  final d = DateTime.tryParse(isoDate);
  if (d == null) return null;
  return toISODate(DateTime(d.year, d.month + months, d.day));
}

/// `2026 年 11 月 19 日 · 周三`
String todayText() {
  final d = DateTime.now();
  const week = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${d.year} 年 ${d.month} 月 ${d.day} 日 · ${week[d.weekday - 1]}';
}

/// 按时段问候
String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return '夜深了';
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}
