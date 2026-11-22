/// BoxBook Cloud 服务端启动入口
///
/// 用法：dart run bin/server.dart [--port 8800] [--db ./data/boxbook.db] [--no-open-registration]
/// 环境变量：PORT / DB_PATH / OPEN_REGISTRATION（0 关闭注册）
library;

import 'dart:io';

import 'package:boxbook_server/boxbook_server.dart';

Future<void> main(List<String> args) async {
  String readArg(String name, String envKey, String defaultValue) {
    final i = args.indexOf('--$name');
    if (i >= 0 && i + 1 < args.length) return args[i + 1];
    final env = Platform.environment[envKey];
    if (env != null && env.isNotEmpty) return env;
    return defaultValue;
  }

  final port = int.parse(readArg('port', 'PORT', '8800'));
  final dbPath = readArg('db', 'DB_PATH', './data/boxbook.db');
  final openRegistration =
      readArg('open-registration', 'OPEN_REGISTRATION', '1') != '0';

  final store = BoxStore(dbPath)..load();
  final server = await startBoxBookServer(
    store: store,
    port: port,
    openRegistration: openRegistration,
    webDir: 'web',
  );

  stdout.writeln('''
BoxBook Cloud 服务端已启动
  地址: http://${server.address.address}:${server.port}
  数据: $dbPath
  注册: ${openRegistration ? '开放' : '已关闭'}
  Web 管理页: http://${server.address.address}:${server.port}/
''');
}
