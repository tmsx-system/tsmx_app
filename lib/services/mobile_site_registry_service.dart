import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class RegisteredMobileSite {
  final String siteName;
  final String siteCode;
  final String siteUrl;
  final bool enabled;

  const RegisteredMobileSite({
    required this.siteName,
    required this.siteCode,
    required this.siteUrl,
    required this.enabled,
  });

  factory RegisteredMobileSite.fromJson(Map<String, dynamic> json) {
    final siteName =
        json['site_name']?.toString() ?? json['name']?.toString() ?? 'ERP Site';
    final siteCode = json['site_code']?.toString() ?? '';
    final siteUrl = json['site_url']?.toString() ?? '';
    final enabledValue = json['enabled'];
    return RegisteredMobileSite(
      siteName: siteName,
      siteCode: siteCode,
      siteUrl: siteUrl,
      enabled:
          enabledValue == true ||
          enabledValue == 1 ||
          enabledValue?.toString() == '1',
    );
  }
}

class MobileSiteRegistryService {
  MobileSiteRegistryService({this.client});

  static const Duration _requestTimeout = Duration(seconds: 15);

  final http.Client? client;

  Future<RegisteredMobileSite> resolveSite(String codeOrUrl) async {
    final key = codeOrUrl.trim();
    if (key.isEmpty) throw Exception('Kode perusahaan/site wajib diisi.');

    final activeClient = client ?? http.Client();
    final shouldCloseClient = client == null;
    try {
      return await _resolveViaPublicMethod(activeClient, key);
    } finally {
      if (shouldCloseClient) activeClient.close();
    }
  }

  Future<Map<String, dynamic>> registerSite({
    required String siteName,
    required String siteCode,
    required String siteUrl,
    required String frappeVersion,
    required String erpnextVersion,
    required String contactName,
    required String phoneNumber,
    bool enabled = true,
  }) async {
    final activeClient = client ?? http.Client();
    final shouldCloseClient = client == null;
    try {
      final uri = Uri.parse(
        '${AppConfig.mobileSiteRegistryBaseUrl}/api/method/register_mobile_site',
      );
      final response = await activeClient
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'site_name': siteName.trim(),
              'site_code': siteCode.trim().toLowerCase(),
              'site_url': _normalizeUrl(siteUrl),
              'frappe_version': frappeVersion.trim(),
              'erpnext_version': erpnextVersion.trim(),
              'contact_name': contactName.trim(),
              'phone_number': phoneNumber.trim(),
            }),
          )
          .timeout(_requestTimeout);
      final decoded = _tryDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractFrappeError(decoded, response.statusCode));
      }
      final data = decoded is Map ? decoded['message'] : null;
      if (data is Map<String, dynamic>) {
        if (data['success'] == false) {
          throw Exception(data['message']?.toString() ?? 'Register gagal.');
        }
        return data;
      }
      if (data is Map) {
        final mapped = Map<String, dynamic>.from(data);
        if (mapped['success'] == false) {
          throw Exception(mapped['message']?.toString() ?? 'Register gagal.');
        }
        return mapped;
      }
      return const {};
    } finally {
      if (shouldCloseClient) activeClient.close();
    }
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  Future<RegisteredMobileSite> _resolveViaPublicMethod(
    http.Client activeClient,
    String codeOrUrl,
  ) async {
    final uri = Uri.parse(
      '${AppConfig.mobileSiteRegistryBaseUrl}/api/method/check_mobile_site',
    );
    final response = await activeClient
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: {
            'code_or_url': codeOrUrl,
            'site_code': codeOrUrl.trim().toLowerCase(),
            'site_url': _normalizeUrl(codeOrUrl),
          },
        )
        .timeout(_requestTimeout);
    final decoded = _tryDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }
    final message = decoded is Map ? decoded['message'] : null;
    final data = message is Map ? Map<String, dynamic>.from(message) : null;
    if (data == null) throw Exception('Response registry tidak valid.');
    if (data['success'] == false) {
      throw Exception(data['message']?.toString() ?? 'Site tidak valid.');
    }
    return RegisteredMobileSite.fromJson(data);
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  String _extractFrappeError(dynamic decoded, int statusCode) {
    if (decoded is Map) {
      final exception = decoded['exception']?.toString();
      if (exception != null && exception.trim().isNotEmpty) return exception;
      final message = decoded['_server_messages'];
      final parsed = _serverMessage(message);
      if (parsed.isNotEmpty) return parsed;
      final exc = decoded['exc']?.toString();
      if (exc != null && exc.trim().isNotEmpty) return exc;
      final direct = decoded['message']?.toString();
      if (direct != null && direct.trim().isNotEmpty) return direct;
    }
    return 'Gagal register site. HTTP $statusCode';
  }

  String _serverMessage(dynamic raw) {
    if (raw == null) return '';
    try {
      final outer = raw is String ? jsonDecode(raw) : raw;
      if (outer is! List || outer.isEmpty) return '';
      final first = outer.first;
      final decoded = first is String ? jsonDecode(first) : first;
      if (decoded is Map) {
        return decoded['message']
                ?.toString()
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .trim() ??
            '';
      }
    } catch (_) {}
    return raw.toString();
  }
}
