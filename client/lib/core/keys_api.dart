import 'dart:convert';

import 'package:http/http.dart' as http;

import '../crypto/identity.dart';

/// Sunucu key bundle REST API istemcisi.
class KeysApi {
  KeysApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// Public bundle'ı yükler. 204 → başarı; başka kod → exception.
  Future<void> uploadBundle(PublicKeyBundle bundle) async {
    final r = await _client.post(
      _u('/api/v1/keys/bundle'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(bundle.toJson()),
    );
    if (r.statusCode != 204) {
      throw KeysApiException(
        'uploadBundle failed: ${r.statusCode} ${r.body}',
        r.statusCode,
      );
    }
  }

  /// Karşı tarafın bundle'ını çeker (server bir OPK'yı atomik tüketir).
  /// 404 → kullanıcı yok → null döner.
  Future<FetchedBundle?> fetchBundle(String handle) async {
    final r = await _client.get(_u('/api/v1/keys/bundle/$handle'));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw KeysApiException(
        'fetchBundle failed: ${r.statusCode} ${r.body}',
        r.statusCode,
      );
    }
    return FetchedBundle.fromJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  Future<int> opkCount(String handle) async {
    final r = await _client.get(_u('/api/v1/keys/bundle/$handle/stats'));
    if (r.statusCode != 200) {
      throw KeysApiException(
        'opkCount failed: ${r.statusCode}',
        r.statusCode,
      );
    }
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return m['opk_count'] as int;
  }

  void close() => _client.close();
}

class KeysApiException implements Exception {
  KeysApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => 'KeysApiException($statusCode): $message';
}
