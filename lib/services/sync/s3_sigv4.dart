/// AWS Signature Version 4（S3 签名，兼容 AWS S3 / Cloudflare R2 / MinIO）
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 为 S3 请求生成 SigV4 认证头
class S3SigV4 {
  S3SigV4._();

  /// 生成请求头（host 由调用方另行设置）。
  ///
  /// [method] HTTP 方法；[uri] 已含 bucket/key 路径（path-style）；
  /// [region] 区域（R2 用 auto）；[payload] 请求体字节。
  static Map<String, String> sign({
    required String method,
    required Uri uri,
    required String region,
    required String accessKey,
    required String secretKey,
    required List<int> payload,
    required DateTime now,
  }) {
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final payloadHash = sha256.convert(payload).toString();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final emptyUri = uri.path.isEmpty || uri.path == '/';
    final canonicalUri = emptyUri ? '/' : _encodePath(uri.path);

    final canonicalHeaders =
        'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = [
      method,
      canonicalUri,
      uri.query.isEmpty ? '' : '${uri.query}\n', // 查询串需排序；本项目无查询参数
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final scope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _hmacKey(secretKey, dateStamp, region);
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    return {
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }

  /// path-style 的路径编码：保留 `/`，其余按 RFC3986 编码
  static String _encodePath(String path) {
    return path.split('/').map(Uri.encodeComponent).join('/');
  }

  static String _amzDate(DateTime now) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${now.toUtc().year}${p(now.toUtc().month)}${p(now.toUtc().day)}'
        'T${p(now.toUtc().hour)}${p(now.toUtc().minute)}${p(now.toUtc().second)}Z';
  }

  static List<int> _hmacKey(String secret, String date, String region) {
    var key = Hmac(sha256, utf8.encode('AWS4$secret'))
        .convert(utf8.encode(date))
        .bytes;
    key = Hmac(sha256, key).convert(utf8.encode(region)).bytes;
    key = Hmac(sha256, key).convert(utf8.encode('s3')).bytes;
    return Hmac(sha256, key).convert(utf8.encode('aws4_request')).bytes;
  }
}
