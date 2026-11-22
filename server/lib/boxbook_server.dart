/// BoxBook Cloud 自托管同步服务端。
///
/// 多用户注册/登录（token 认证）、多「物品册」（每本 = 一份完整的物盒册数据快照）、
/// 共享与角色（owner / editor / viewer）、内置 Web 管理页。
/// 数据以 JSON 文件落盘（原子写入），无外部数据库依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

final Random _secureRandom = Random.secure();

String _newToken() => List.generate(32, (_) => _secureRandom.nextInt(256))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

String _hashPassword(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();

String _nowIso() => DateTime.now().toUtc().toIso8601String();

/* ------------------------- 数据模型与文件存储 ------------------------- */

class BoxUser {
  BoxUser({required this.username, required this.salt, required this.passHash, required this.createdAt});

  final String username;
  final String salt;
  final String passHash;
  final String createdAt;

  Map<String, dynamic> toJson() =>
      {'username': username, 'salt': salt, 'passHash': passHash, 'createdAt': createdAt};

  factory BoxUser.fromJson(Map<String, dynamic> json) => BoxUser(
        username: json['username'] as String,
        salt: json['salt'] as String,
        passHash: json['passHash'] as String,
        createdAt: json['createdAt'] as String,
      );
}

class BoxBookRecord {
  BoxBookRecord({
    required this.id,
    required this.owner,
    required this.name,
    required this.members, // username → owner / editor / viewer
    this.data = '',
    this.dataUpdatedAt,
    this.dataWriter,
    required this.createdAt,
  });

  final int id;
  final String owner;
  String name;

  /// username → role
  final Map<String, String> members;
  String data;
  String? dataUpdatedAt;
  String? dataWriter;
  final String createdAt;

  String? roleOf(String username) {
    if (owner == username) return 'owner';
    return members[username];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'name': name,
        'members': members,
        'data': data,
        'dataUpdatedAt': dataUpdatedAt,
        'dataWriter': dataWriter,
        'createdAt': createdAt,
      };

  factory BoxBookRecord.fromJson(Map<String, dynamic> json) => BoxBookRecord(
        id: (json['id'] as num).toInt(),
        owner: json['owner'] as String,
        name: json['name'] as String,
        members: (json['members'] as Map?)?.cast<String, String>() ?? {},
        data: json['data'] as String? ?? '',
        dataUpdatedAt: json['dataUpdatedAt'] as String?,
        dataWriter: json['dataWriter'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
      );
}

class BoxData {
  BoxData({
    required this.users,
    required this.tokens, // token → username
    required this.books,
    required this.nextBookId,
  });

  List<BoxUser> users;
  Map<String, String> tokens;
  List<BoxBookRecord> books;
  int nextBookId;

  BoxUser? findUser(String username) {
    for (final u in users) {
      if (u.username == username) return u;
    }
    return null;
  }

  BoxBookRecord? findBook(int id) {
    for (final b in books) {
      if (b.id == id) return b;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'users': users.map((u) => u.toJson()).toList(),
        'tokens': tokens,
        'books': books.map((b) => b.toJson()).toList(),
        'nextBookId': nextBookId,
      };

  factory BoxData.fromJson(Map<String, dynamic> json) => BoxData(
        users: ((json['users'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BoxUser.fromJson)
            .toList(),
        tokens: (json['tokens'] as Map?)?.cast<String, String>() ?? {},
        books: ((json['books'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BoxBookRecord.fromJson)
            .toList(),
        nextBookId: (json['nextBookId'] as num?)?.toInt() ?? 1,
      );
}

/// JSON 文件存储（原子写入：临时文件 + 重命名）
class BoxStore {
  BoxStore(this.dataPath);

  final String dataPath;
  late BoxData data;

  void load() {
    final file = File(dataPath);
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        data = BoxData.fromJson(decoded as Map<String, dynamic>);
        return;
      } catch (err) {
        stderr.writeln('数据文件解析失败，已重新初始化：$err');
      }
    }
    data = BoxData(users: [], tokens: {}, books: [], nextBookId: 1);
    save();
  }

  void save() {
    final file = File(dataPath);
    Directory(file.parent.path).createSync(recursive: true);
    final tmpFile = File('$dataPath.tmp')
      ..writeAsStringSync(jsonEncode(data.toJson()), flush: true);
    if (file.existsSync()) file.deleteSync();
    tmpFile.renameSync(dataPath);
  }
}

/* ------------------------- 服务端 ------------------------- */

class BoxBookServer {
  BoxBookServer({required this.store, this.openRegistration = true, this.webDir});

  final BoxStore store;
  final bool openRegistration;
  final String? webDir;
  HttpServer? _server;

  Future<HttpServer> start({int port = 8800, Object? address}) async {
    final handler = const Pipeline()
        .addMiddleware(_errors())
        .addHandler(_router.call);
    _server = await shelf_io.serve(handler, address ?? InternetAddress.anyIPv4, port);
    return _server!;
  }

  Future<void> stop() async => _server?.close(force: true);

  /* ---------- 中间件与工具 ---------- */

  Middleware _errors() => (inner) => (request) async {
        try {
          return await inner(request);
        } catch (err) {
          return _json({'error': '服务器内部错误：$err'}, 500);
        }
      };

  Response _json(Object? data, [int status = 200]) => Response(
        status,
        body: jsonEncode(data),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );

  Future<Map<String, dynamic>?> _jsonBody(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.isEmpty) return {};
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  String? _authUser(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) return null;
    final token = header.substring(7).trim();
    return store.data.tokens[token];
  }

  /* ---------- 路由 ---------- */

  Router get _router {
    final router = Router();
    router.get('/', _webPageHandler);
    router.post('/api/register', _register);
    router.post('/api/login', _login);
    router.get('/api/books', _listBooks);
    router.post('/api/books', _createBook);
    router.put('/api/books/<id>', _renameBook);
    router.delete('/api/books/<id>', _deleteBook);
    router.post('/api/books/<id>/share', _shareBook);
    router.get('/api/books/<id>/members', _listMembers);
    router.get('/api/books/<id>/data', _getData);
    router.put('/api/books/<id>/data', _putData);
    return router;
  }

  Future<Response> _webPageHandler(Request request) async {
    final dir = webDir ?? 'web';
    final file = File('$dir/index.html');
    if (file.existsSync()) {
      return Response.ok(
        file.readAsStringSync(),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }
    return Response.ok('<h1>BoxBook Cloud</h1><p>web/index.html 未找到</p>',
        headers: {'Content-Type': 'text/html; charset=utf-8'});
  }

  Future<Response> _register(Request request) async {
    if (!openRegistration) {
      return _json({'error': '服务端已关闭注册'}, 403);
    }
    final body = await _jsonBody(request);
    final username = body?['username']?.toString().trim() ?? '';
    final password = body?['password']?.toString() ?? '';
    if (username.length < 2 || password.length < 4) {
      return _json({'error': '用户名至少 2 位，密码至少 4 位'}, 400);
    }
    if (store.data.findUser(username) != null) {
      return _json({'error': '用户名已存在'}, 400);
    }
    final salt = _newToken().substring(0, 16);
    final user = BoxUser(
      username: username,
      salt: salt,
      passHash: _hashPassword(password, salt),
      createdAt: _nowIso(),
    );
    store.data.users.add(user);
    final token = _newToken();
    store.data.tokens[token] = username;
    store.save();
    return _json({'token': token, 'username': username});
  }

  Future<Response> _login(Request request) async {
    final body = await _jsonBody(request);
    final username = body?['username']?.toString() ?? '';
    final password = body?['password']?.toString() ?? '';
    final user = store.data.findUser(username);
    if (user == null || _hashPassword(password, user.salt) != user.passHash) {
      return _json({'error': '用户名或密码错误'}, 401);
    }
    final token = _newToken();
    store.data.tokens[token] = username;
    store.save();
    return _json({'token': token, 'username': username});
  }

  /// 物品册列表：自己的 + 共享给我的
  Future<Response> _listBooks(Request request) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final books = store.data.books.where((b) => b.roleOf(username) != null).map((b) {
      return {
        'id': b.id,
        'name': b.name,
        'role': b.roleOf(username),
        'ownerName': b.owner,
        'updatedAt': b.dataUpdatedAt,
        'memberCount': b.members.length,
      };
    }).toList();
    return _json({'books': books});
  }

  Future<Response> _createBook(Request request) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final body = await _jsonBody(request);
    final name = body?['name']?.toString().trim() ?? '';
    if (name.isEmpty || name.length > 40) {
      return _json({'error': '物品册名称需 1-40 个字符'}, 400);
    }
    final id = store.data.nextBookId++;
    final book = BoxBookRecord(
      id: id,
      owner: username,
      name: name,
      members: {username: 'owner'},
      createdAt: _nowIso(),
    );
    store.data.books.add(book);
    store.save();
    return _json({'book': book.toJson()});
  }

  Future<Response> _renameBook(Request request, String id) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final book = store.data.findBook(int.tryParse(id) ?? -1);
    if (book == null) return _json({'error': '物品册不存在'}, 404);
    if (book.roleOf(username) != 'owner') return _json({'error': '仅创建者可改名'}, 403);
    final body = await _jsonBody(request);
    final name = body?['name']?.toString().trim() ?? '';
    if (name.isEmpty) return _json({'error': '名称不能为空'}, 400);
    book.name = name;
    store.save();
    return _json({'book': book.toJson()});
  }

  Future<Response> _deleteBook(Request request, String id) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final book = store.data.findBook(int.tryParse(id) ?? -1);
    if (book == null) return _json({'error': '物品册不存在'}, 404);
    if (book.roleOf(username) != 'owner') return _json({'error': '仅创建者可删除'}, 403);
    store.data.books.removeWhere((b) => b.id == book.id);
    store.save();
    return _json({'ok': true});
  }

  Future<Response> _shareBook(Request request, String id) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final book = store.data.findBook(int.tryParse(id) ?? -1);
    if (book == null) return _json({'error': '物品册不存在'}, 404);
    if (book.roleOf(username) != 'owner') return _json({'error': '仅创建者可共享'}, 403);
    final body = await _jsonBody(request);
    final targetUser = body?['username']?.toString().trim() ?? '';
    final role = body?['role']?.toString() ?? 'editor';
    if (!['editor', 'viewer'].contains(role)) {
      return _json({'error': '角色只能是 editor 或 viewer'}, 400);
    }
    if (store.data.findUser(targetUser) == null) {
      return _json({'error': '用户 $targetUser 不存在（对方需先注册）'}, 400);
    }
    if (targetUser == username) {
      return _json({'error': '不能共享给自己'}, 400);
    }
    book.members[targetUser] = role;
    store.save();
    return _json({'ok': true});
  }

  Future<Response> _listMembers(Request request, String id) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final book = store.data.findBook(int.tryParse(id) ?? -1);
    if (book == null) return _json({'error': '物品册不存在'}, 404);
    if (book.roleOf(username) != 'owner') return _json({'error': '仅创建者可查看成员'}, 403);
    return _json({'members': book.members});
  }

  Future<Response> _getData(Request request, String id) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final book = store.data.findBook(int.tryParse(id) ?? -1);
    if (book == null) return _json({'error': '物品册不存在'}, 404);
    final role = book.roleOf(username);
    if (role == null) return _json({'error': '没有访问权限'}, 403);
    return _json({
      'content': book.data,
      'updatedAt': book.dataUpdatedAt,
      'writerName': book.dataWriter,
    });
  }

  Future<Response> _putData(Request request, String id) async {
    final username = _authUser(request);
    if (username == null) return _json({'error': '未登录'}, 401);
    final book = store.data.findBook(int.tryParse(id) ?? -1);
    if (book == null) return _json({'error': '物品册不存在'}, 404);
    final role = book.roleOf(username);
    if (role == 'viewer') return _json({'error': '只读成员无写入权限'}, 403);
    final body = await _jsonBody(request);
    final content = body?['content']?.toString();
    if (content == null || content.isEmpty) return _json({'error': '缺少备份内容'}, 400);
    book.data = content;
    book.dataUpdatedAt = _nowIso();
    book.dataWriter = username;
    store.save();
    return _json({'ok': true, 'updatedAt': book.dataUpdatedAt});
  }
}

/// 启动服务（测试与 bin/server.dart 共用）
Future<HttpServer> startBoxBookServer({
  required BoxStore store,
  int port = 8800,
  Object? address,
  bool openRegistration = true,
  String? webDir,
}) {
  final server = BoxBookServer(
    store: store,
    openRegistration: openRegistration,
    webDir: webDir,
  );
  return server.start(port: port, address: address);
}
