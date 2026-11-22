/// Supabase 同步后端（免费额度充足的开源后端）
///
/// 使用前需在 Supabase SQL Editor 中执行一次建表 SQL（设置页有提供）：
/// ```sql
/// create table if not exists wuhece_backups (
///   id text primary key,
///   content text,
///   updated_at timestamptz default now()
/// );
/// alter table wuhece_backups enable row level security;
/// create policy "anon all" on wuhece_backups for all using (true) with check (true);
/// ```
library;

import 'package:supabase/supabase.dart';

import 'sync_backend.dart';

class SupabaseBackend implements SyncBackend {
  SupabaseBackend({
    required this.url,
    required this.anonKey,
    this.table = 'wuhece_backups',
    this.rowId = 'default',
  });

  /// Project URL，如 https://xxxx.supabase.co
  final String url;
  final String anonKey;
  final String table;
  final String rowId;

  SupabaseClient? _client;
  SupabaseClient get _clientImpl => _client ??= SupabaseClient(url, anonKey);

  static const setupSql =
      "create table if not exists wuhece_backups (\n"
      "  id text primary key,\n"
      "  content text,\n"
      "  updated_at timestamptz default now()\n"
      ");\n"
      "alter table wuhece_backups enable row level security;\n"
      'create policy "wuhece anon" on wuhece_backups for all using (true) with check (true);';

  String _mapError(Object err) {
    final text = err.toString();
    if (text.contains('relation') && text.contains('does not exist')) {
      return 'Supabase 中还没有备份表，请在 SQL Editor 执行设置页提供的建表 SQL';
    }
    if (text.contains('Invalid API key') || text.contains('JWT')) {
      return 'Anon Key 无效，请检查 Project URL 与 Anon Key';
    }
    return 'Supabase 请求失败：$err';
  }

  @override
  Future<void> testConnection() async {
    try {
      await _clientImpl.from(table).select('id').limit(1);
    } catch (err) {
      throw SyncException(_mapError(err));
    }
  }

  @override
  Future<void> upload(String content) async {
    try {
      await _clientImpl.from(table).upsert({
        'id': rowId,
        'content': content,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (err) {
      throw SyncException(_mapError(err));
    }
  }

  @override
  Future<String?> download() async {
    try {
      final rows = await _clientImpl.from(table).select('content').eq('id', rowId).limit(1);
      if (rows.isEmpty) return null;
      return rows.first['content']?.toString();
    } catch (err) {
      throw SyncException(_mapError(err));
    }
  }
}
