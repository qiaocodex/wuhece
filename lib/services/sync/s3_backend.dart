/// S3 协议同步后端（AWS S3 / Cloudflare R2 / MinIO，SigV4 自研签名）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 's3_sigv4.dart';
import 'sync_backend.dart';

class S3Backend implements SyncBackend {
  S3Backend({
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    this.objectPath = 'wuhece/backup.json',
  });

  /// 服务地址（不含桶名）：AWS https://s3.amazonaws.com、
  /// R2 `https://<account>.r2.cloudflarestorage.com`、MinIO `http://host:9000`
  final String endpoint;
  final String region; // R2 用 auto
  final String accessKey;
  final String secretKey;
  final String bucket;

  /// 桶内对象键（如 wuhece/backup.json）
  final String objectPath;

  http.Client? _client;
  http.Client get _http => _client ??= http.Client();

  Uri _objectUri() {
    final base = Uri.parse(
      endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint,
    );
    final key = objectPath.startsWith('/') ? objectPath.substring(1) : objectPath;
    final port = base.hasPort ? ':${base.port}' : '';
    final scheme = base.scheme.isEmpty ? 'https' : base.scheme;
    return Uri.parse('$scheme://${base.host}$port/$bucket/$key');
  }

  Uri _bucketUri() {
    final base = Uri.parse(
      endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint,
    );
    final port = base.hasPort ? ':${base.port}' : '';
    final scheme = base.scheme.isEmpty ? 'https' : base.scheme;
    return Uri.parse('$scheme://${base.host}$port/$bucket');
  }

  Map<String, String> _signedHeaders(
    String method,
    Uri uri,
    List<int> payload, {
    Map<String, String>? extra,
  }) {
    final now = DateTime.now();
    final result = <String, String>{
      'Host': uri.hasPort ? '${uri.host}:${uri.port}' : uri.host,
      ...S3SigV4.sign(
        method: method,
        uri: uri,
        region: region,
        accessKey: accessKey,
        secretKey: secretKey,
        payload: payload,
        now: now,
      ),
    };
    if (extra != null) result.addAll(extra);
    return result;
  }

  String _mapError(Object err, int? statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'S3 鉴权失败，请检查 Access Key / Secret Key';
    }
    if (statusCode == 404) {
      return '存储桶或对象不存在';
    }
    return 'S3 请求失败：$err';
  }

  @override
  Future<void> testConnection() async {
    try {
      final uri = _bucketUri();
      final response = await _http
          .get(uri, headers: _signedHeaders('GET', uri, utf8.encode('')))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) {
        throw SyncException('存储桶「$bucket」不存在，请先在控制台创建');
      }
      if (response.statusCode >= 400) {
        throw SyncException(_mapError(response.body, response.statusCode));
      }
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('无法连接 S3 服务：$err');
    }
  }

  @override
  Future<void> upload(String content) async {
    final uri = _objectUri();
    final payload = Uint8List.fromList(utf8.encode(content));
    try {
      final response = await _http
          .put(uri, headers: _signedHeaders('PUT', uri, payload), body: payload)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 300) {
        throw SyncException(_mapError(response.body, response.statusCode));
      }
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('上传失败：$err');
    }
  }

  @override
  Future<String?> download() async {
    final uri = _objectUri();
    try {
      final response = await _http
          .get(uri, headers: _signedHeaders('GET', uri, utf8.encode('')))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 404) return null;
      if (response.statusCode >= 300) {
        throw SyncException(_mapError(response.body, response.statusCode));
      }
      return utf8.decode(response.bodyBytes);
    } on SyncException {
      rethrow;
    } catch (err) {
      throw SyncException('下载失败：$err');
    }
  }
}
