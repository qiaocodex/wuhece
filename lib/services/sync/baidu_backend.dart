/// 百度网盘开放平台同步后端。
///
/// 授权：设备码模式（openapi.baidu.com/oauth/2.0/device/code），无需配置回调
/// 地址，四端通用——用户在任意浏览器打开授权页输入 user_code 完成授权。
/// 文件：pan.baidu.com/rest/2.0/xpan 系列接口，应用数据存放在网盘
/// `/apps/<应用名>/` 专属目录；小文件单步上传，大文件预上传→分片→create。
///
/// 使用前提：用户需在 pan.baidu.com/union 注册开发者并创建应用，
/// 取得 AppKey/SecretKey（百度禁止共享开发者账号，只能自备）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import 'sync_backend.dart';

/// 百度网盘开放平台 OAuth 与文件接口客户端
class BaiduBackend implements SyncBackend {
  BaiduBackend({
    required this.appKey,
    required this.secretKey,
    required this.accessToken,
    this.refreshToken = '',
    this.remoteDir = '/apps/物盒册',
    http.Client? client,
    this.onTokenRefreshed,
  }) : _client = client ?? http.Client();

  static const _oauthBase = 'https://openapi.baidu.com/oauth/2.0';
  static const _apiBase = 'https://pan.baidu.com/rest/2.0';
  static const _uploadBase = 'https://d.pcs.baidu.com/rest/2.0';
  static const _partSize = 4 * 1024 * 1024; // 分片上传单片上限 4MB

  final String appKey;
  final String secretKey;
  final String accessToken;
  final String refreshToken;
  final String remoteDir;
  final http.Client _client;

  /// access_token 续期后回写（供上层持久化到 SyncSettings）
  final void Function(String accessToken, String refreshToken, int expiresInSeconds)? onTokenRefreshed;

  bool get authorized => accessToken.isNotEmpty;

  /* ------------------------- 设备码授权 ------------------------- */

  /// 第一步：申请设备码（UI 展示 user_code，并打开 verification_url）
  Future<BaiduDeviceCode> requestDeviceCode() async {
    final resp = await _client.post(
      Uri.parse('$_oauthBase/device/code'),
      body: {'client_id': appKey, 'scope': 'basic,netdisk'},
    );
    final data = _decode(resp, '申请设备码');
    if (data['device_code'] == null) {
      throw SyncException('申请设备码失败：${data['error'] ?? resp.body}');
    }
    return BaiduDeviceCode(
      deviceCode: data['device_code'].toString(),
      userCode: data['user_code']?.toString() ?? '',
      verificationUrl: data['verification_url']?.toString() ?? 'https://openapi.baidu.com/device',
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 300,
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
    );
  }

  /// 第二步：轮询等待用户在浏览器完成授权；成功返回 token 并刷新回调。
  /// [timeout] 到期或设备码过期抛 [SyncException]。
  Future<BaiduToken> pollForToken(BaiduDeviceCode code, {Duration timeout = const Duration(minutes: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    var interval = Duration(seconds: code.intervalSeconds.clamp(1, 15));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      final resp = await _client.post(Uri.parse('$_oauthBase/token'), body: {
        'grant_type': 'device_token',
        'client_id': appKey,
        'client_secret': secretKey,
        'code': code.deviceCode,
      });
      final data = _decode(resp, '等待授权');
      if (data['access_token'] != null) {
        final token = BaiduToken(
          accessToken: data['access_token'].toString(),
          refreshToken: data['refresh_token']?.toString() ?? refreshToken,
          expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 2592000,
        );
        onTokenRefreshed?.call(token.accessToken, token.refreshToken, token.expiresInSeconds);
        return token;
      }
      final err = data['error']?.toString();
      switch (err) {
        case 'authorization_pending':
          continue; // 用户尚未确认，继续轮询
        case 'slow_down':
          interval = Duration(seconds: interval.inSeconds + 5);
          continue;
        case 'authorization_expired' || 'expired_token':
          throw SyncException('授权已过期，请重新发起登录');
        default:
          throw SyncException('授权失败：${err ?? resp.body}');
      }
    }
    throw SyncException('等待授权超时，请重新发起登录');
  }

  /// 用 refresh_token 续期 access_token（30 天过期前由请求自动触发）
  Future<String?> _ensureFreshToken() async {
    if (refreshToken.isEmpty) return null;
    final resp = await _client.post(Uri.parse('$_oauthBase/token'), body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': appKey,
      'client_secret': secretKey,
    });
    try {
      final data = _decode(resp, '续期');
      if (data['access_token'] == null) return null;
      onTokenRefreshed?.call(
        data['access_token'].toString(),
        data['refresh_token']?.toString() ?? refreshToken,
        (data['expires_in'] as num?)?.toInt() ?? 2592000,
      );
      return data['access_token'].toString();
    } catch (_) {
      return null; // 续期失败按原 token 继续尝试
    }
  }

  /* ------------------------- SyncBackend ------------------------- */

  @override
  Future<void> testConnection() async {
    // 用户信息接口顺带验证 token 有效性；失败触发一次续期重试
    Map<String, dynamic>? info;
    try {
      info = await _uinfo();
    } on SyncException {
      final fresh = await _ensureFreshToken();
      if (fresh == null) rethrow;
      info = await _uinfo();
    }
    if (info == null) throw SyncException('百度网盘未授权或授权已过期');
    // 远程目录可列（不存在时网盘会在上传时自动创建）
    await _listDir(_normalizedDir);
  }

  @override
  Future<void> upload(String content) async {
    var token = accessToken;
    if (token.isEmpty) throw SyncException('请先登录百度网盘');
    final bytes = Uint8List.fromList(utf8.encode(content));
    final path = '$_normalizedDir/backup.json';

    // 覆盖前把远端旧备份复制到 history 目录（尽力而为，失败不阻断）
    await _archivePrevious(path, token);

    if (bytes.length <= _partSize) {
      await _uploadSingle(path, bytes, token);
      return;
    }

    // 大文件：预上传 → 分片上传 → create 合并
    final blockList = [for (var i = 0; i < bytes.length; i += _partSize) _md5(bytes.sublist(i, (i + _partSize).clamp(0, bytes.length)))];
    final uploadId = await _precreate(path, bytes.length, blockList, token);
    var seq = 0;
    for (var i = 0; i < bytes.length; i += _partSize) {
      final end = (i + _partSize).clamp(0, bytes.length);
      await _uploadPart(path, uploadId, seq++, Uint8List.sublistView(bytes, i, end), token);
    }
    await _createFile(path, bytes.length, uploadId, blockList, token);
  }

  @override
  Future<String?> download() async {
    final token = accessToken;
    if (token.isEmpty) throw SyncException('请先登录百度网盘');
    final resp = await _get(
      Uri.parse('$_apiBase/xpan/file?method=download&access_token=$token&path=${Uri.encodeComponent('$_normalizedDir/backup.json')}'),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      // 网盘对不存在的文件常返回 200 + errno JSON
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      if (body.contains('"errno"')) return null;
      throw SyncException('下载失败：HTTP ${resp.statusCode}');
    }
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (body.contains('"errno"')) {
      final data = jsonDecode(body);
      if (data is Map && (data['errno'] != 0)) return null; // 文件不存在等
      return null;
    }
    return body;
  }

  /* ------------------------- 授权信息 ------------------------- */

  /// 当前授权账号昵称（设置页展示）；未授权返回空
  Future<String> fetchNickname() async {
    final info = await _uinfo();
    return (info?['netdisk_name'] ?? info?['baidu_name'] ?? '').toString();
  }

  /* ------------------------- 内部 HTTP ------------------------- */

  String get _normalizedDir {
    final dir = remoteDir.trim();
    if (dir.isEmpty) return '/apps/物盒册';
    return dir.startsWith('/') ? dir : '/$dir';
  }

  Map<String, dynamic> _decode(http.Response resp, String what) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true)) as Map<String, dynamic>;
    } catch (_) {
      throw SyncException('$what 失败：接口返回无法解析（HTTP ${resp.statusCode}）');
    }
    if (resp.statusCode != 200) {
      final desc = data['error_description'] ?? data['errormsg'] ?? data['error'] ?? resp.body;
      throw SyncException('$what 失败：$desc');
    }
    return data;
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      _client.get(uri, headers: headers).timeout(const Duration(seconds: 60));

  Future<Map<String, dynamic>?> _uinfo() async {
    final resp = await _get(Uri.parse('$_apiBase/xpan/nas?method=uinfo&access_token=$accessToken'));
    if (resp.statusCode != 200) return null;
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 列目录；目录不存在或为空返回空列表
  Future<List<Map<String, dynamic>>> _listDir(String dir) async {
    final resp = await _get(Uri.parse(
        '$_apiBase/xpan/file?method=list&access_token=$accessToken&dir=${Uri.encodeComponent(dir)}&limit=100&web=1'));
    if (resp.statusCode != 200) {
      throw SyncException('无法访问网盘目录 $dir（HTTP ${resp.statusCode}），请检查远程目录与授权');
    }
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    try {
      final data = jsonDecode(body);
      if (data is! Map) return const [];
      final errno = (data['errno'] as num?)?.toInt() ?? 0;
      if (errno != 0) {
        // 12 = 文件不存在（目录尚未创建，上传时自动创建）
        if (errno == 12) return const [];
        throw SyncException('网盘返回错误 errno=$errno，请检查远程目录与授权权限');
      }
      return ((data['list'] as List?) ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    } on SyncException {
      rethrow;
    } catch (_) {
      throw SyncException('网盘返回内容无法解析');
    }
  }

  /// 覆盖前把远端现有备份复制到 history/（失败静默，不阻断主流程）
  Future<void> _archivePrevious(String path, String token) async {
    try {
      final existing = await _listDir(_normalizedDir);
      final hasBackup = existing.any((f) => f['path'] == path || f['server_filename'] == 'backup.json');
      if (!hasBackup) return;
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      await _client.post(
        Uri.parse('$_apiBase/xpan/filemanager?method=copy&access_token=$token'),
        body: {
          'filelist': jsonEncode([
            {'path': path, 'dest': _historyDir, 'newname': 'backup-$stamp.json'},
          ]),
        },
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      // 历史归档失败不影响同步
    }
  }

  String get _historyDir => '$_normalizedDir/history';

  Future<void> _uploadSingle(String path, Uint8List bytes, String token) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/xpan/file?method=upload&access_token=$token&path=${Uri.encodeComponent(path)}&type=object&overwrite=1'),
    )..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'backup.json'));
    final streamed = await _client.send(req).timeout(const Duration(seconds: 120));
    final resp = await http.Response.fromStream(streamed);
    final data = _decode(resp, '上传备份');
    if (data['errno'] != null && (data['errno'] as num?) != 0) {
      throw SyncException('上传失败：errno=${data['errno']}');
    }
  }

  Future<String> _precreate(String path, int size, List<String> blockList, String token) async {
    final resp = await _client
        .post(
          Uri.parse('$_apiBase/xpan/file?method=precreate&access_token=$token'),
          body: {
            'path': path,
            'size': '$size',
            'isdir': '0',
            'autoinit': '1',
            'block_list': jsonEncode(blockList),
            'rtype': '1',
          },
        )
        .timeout(const Duration(seconds: 60));
    final data = _decode(resp, '预上传');
    final errno = (data['errno'] as num?)?.toInt() ?? 0;
    if (errno != 0 || data['uploadid'] == null) {
      throw SyncException('预上传失败：errno=$errno');
    }
    return data['uploadid'].toString();
  }

  Future<void> _uploadPart(String path, String uploadId, int partseq, Uint8List bytes, String token) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_uploadBase/pcs/superfile2?method=upload&access_token=$token'
          '&type=object&path=${Uri.encodeComponent(path)}&uploadid=$uploadId&partseq=$partseq'),
    )..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'part$partseq'));
    final streamed = await _client.send(req).timeout(const Duration(seconds: 180));
    final resp = await http.Response.fromStream(streamed);
    final data = _decode(resp, '分片上传');
    if ((data['errno'] as num?)?.toInt() != 0) {
      throw SyncException('分片上传失败：errno=${data['errno']}');
    }
  }

  Future<void> _createFile(String path, int size, String uploadId, List<String> blockList, String token) async {
    final resp = await _client
        .post(
          Uri.parse('$_apiBase/xpan/file?method=create&access_token=$token'),
          body: {
            'path': path,
            'size': '$size',
            'isdir': '0',
            'rtype': '1',
            'uploadid': uploadId,
            'block_list': jsonEncode(blockList),
          },
        )
        .timeout(const Duration(seconds: 60));
    final data = _decode(resp, '创建文件');
    if ((data['errno'] as num?)?.toInt() != 0) {
      throw SyncException('创建文件失败：errno=${data['errno']}');
    }
  }

  String _md5(Uint8List bytes) => crypto.md5.convert(bytes).toString();
}

/// 设备码授权第一步的返回
class BaiduDeviceCode {
  const BaiduDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.intervalSeconds,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final int intervalSeconds;
}

/// 授权成功返回的 token
class BaiduToken {
  const BaiduToken({required this.accessToken, required this.refreshToken, required this.expiresInSeconds});

  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;
}
