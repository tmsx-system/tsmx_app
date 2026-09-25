import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../utils/erp_error_message.dart';

class FrappeService {
  static const int maxPageLength = 10000;
  static const Duration _requestTimeout = Duration(seconds: 20);

  String baseUrl;
  String? username;
  String? password;
  final Map<String, String> _cookies = {};

  FrappeService({String? baseUrl})
    : baseUrl = baseUrl ?? AppConfig.optionalFrappeBaseUrl;

  bool get hasCredentials => username != null && password != null;

  Future<void> login(String username, String password) async {
    this.username = username;
    this.password = password;

    final uri = Uri.parse('$baseUrl/api/method/login');
    final response = await _post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'usr': username, 'pwd': password},
    );

    if (response.statusCode != 200) {
      throw Exception('Frappe login failed: ${response.statusCode}');
    }

    final decoded = await _decodeJson(response.body);
    if (decoded is Map && decoded['exc'] != null) {
      throw Exception('Frappe login failed: ${decoded['exc']}');
    }

    if (decoded is Map &&
        decoded['message']?.toString().toLowerCase().contains('invalid') ==
            true) {
      throw Exception('Frappe login failed: invalid username or password.');
    }

    if (_cookies.isEmpty) {
      throw Exception('Frappe login failed: no session cookie received.');
    }
  }

  Future<void> ensureLoggedIn() async {
    if (baseUrl.trim().isEmpty) {
      throw Exception('Frappe site belum dipilih.');
    }
    if (!hasCredentials) {
      throw Exception('Missing Frappe username or password.');
    }

    if (_cookies.isEmpty) {
      await login(username!, password!);
    }
  }

  Future<List<Map<String, dynamic>>> fetchResource(
    String doctype, {
    required List<String> fields,
    int limit = maxPageLength,
    int limitStart = 0,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    await ensureLoggedIn();

    final encodedDoctype = Uri.encodeComponent(doctype);
    final queryParameters = {
      'fields': jsonEncode(fields),
      'limit_page_length': limit.toString(),
      if (limitStart > 0) 'limit_start': limitStart.toString(),
      'order_by': ?orderBy,
      ...filters == null
          ? const <String, String>{}
          : {'filters': jsonEncode(filters)},
      ...orFilters == null
          ? const <String, String>{}
          : {'or_filters': jsonEncode(orFilters)},
    };

    final uri = Uri.parse(
      '$baseUrl/api/resource/$encodedDoctype',
    ).replace(queryParameters: queryParameters);

    if (uri.toString().length > 1800) {
      return _fetchResourceViaClientGetList(
        doctype,
        fields: fields,
        limit: limit,
        limitStart: limitStart,
        orderBy: orderBy,
        filters: filters,
        orFilters: orFilters,
      );
    }

    _DecodedFrappeResponse result;
    try {
      result = await _sendJsonWithRelogin(() => _get(uri), uri: uri);
    } catch (error) {
      if (!_isHtmlResponseError(error)) rethrow;
      return _fetchResourceViaClientGetList(
        doctype,
        fields: fields,
        limit: limit,
        limitStart: limitStart,
        orderBy: orderBy,
        filters: filters,
        orFilters: orFilters,
      );
    }
    final response = result.response;
    final decoded = result.decoded;

    if (response.statusCode != 200) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }

    if (decoded is! Map || decoded['data'] is! List) {
      throw Exception('Invalid Frappe response for $doctype.');
    }

    return (decoded['data'] as List).map((item) {
      return item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item as Map);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchResourceViaClientGetList(
    String doctype, {
    required List<String> fields,
    required int limit,
    required int limitStart,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    final result = await callMethod(
      'frappe.client.get_list',
      args: {
        'doctype': doctype,
        'fields': fields,
        'limit_page_length': limit,
        'limit_start': limitStart,
        if (orderBy != null && orderBy.trim().isNotEmpty) 'order_by': orderBy,
        if (filters != null && filters.isNotEmpty) 'filters': filters,
        if (orFilters != null && orFilters.isNotEmpty) 'or_filters': orFilters,
      },
    );
    final rows = result is Map && result['data'] is List
        ? result['data'] as List
        : result is List
        ? result
        : const [];
    return rows.map((item) {
      return item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item as Map);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchReportView(
    String doctype, {
    required List<String> fields,
    required int limit,
    required int limitStart,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    final result = await callMethod(
      'frappe.desk.reportview.get',
      args: {
        'doctype': doctype,
        'fields': fields,
        'filters': filters ?? const [],
        'or_filters': orFilters ?? const [],
        'order_by': orderBy ?? 'modified desc',
        'start': limitStart,
        'page_length': limit,
        'view': 'List',
        'group_by': null,
        'with_comment_count': 0,
      },
    );

    final payload = result is Map ? Map<String, dynamic>.from(result) : null;
    final rawRows =
        payload?['values'] ?? payload?['data'] ?? payload?['result'];
    if (rawRows is! List) return const [];

    final rawKeys = payload?['keys'] ?? payload?['fields'];
    final keys = rawKeys is List
        ? rawKeys.map((key) => key.toString()).toList()
        : fields;

    return rawRows
        .map((item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return Map<String, dynamic>.from(item);
          if (item is List) {
            final row = <String, dynamic>{};
            for (var i = 0; i < item.length && i < keys.length; i++) {
              final key = _normalizeReportViewKey(keys[i]);
              if (key.isNotEmpty) row[key] = item[i];
            }
            return row;
          }
          return <String, dynamic>{};
        })
        .where((row) => row.isNotEmpty)
        .toList();
  }

  String _normalizeReportViewKey(String raw) {
    var key = raw.split(':').first.trim().replaceAll('`', '');
    final dotIndex = key.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < key.length - 1) {
      key = key.substring(dotIndex + 1);
    }
    return key.trim();
  }

  Future<Map<String, dynamic>> fetchDocument(
    String doctype,
    String name,
  ) async {
    await ensureLoggedIn();

    final encodedDoctype = Uri.encodeComponent(doctype);
    final encodedName = Uri.encodeComponent(name);
    final uri = Uri.parse('$baseUrl/api/resource/$encodedDoctype/$encodedName');

    final result = await _sendJsonWithRelogin(() => _get(uri), uri: uri);
    final response = result.response;
    final decoded = result.decoded;

    if (response.statusCode != 200) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }

    if (decoded is! Map || decoded['data'] is! Map) {
      throw Exception('Invalid Frappe document response for $doctype/$name.');
    }

    final data = decoded['data'];
    return data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> createDocument(
    String doctype,
    Map<String, dynamic> data,
  ) async {
    await ensureLoggedIn();

    final encodedDoctype = Uri.encodeComponent(doctype);
    final uri = Uri.parse('$baseUrl/api/resource/$encodedDoctype');

    final result = await _sendJsonWithRelogin(
      () => _post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ),
      uri: uri,
    );
    final response = result.response;
    final decoded = result.decoded;

    if (response.statusCode != 200) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }

    if (decoded is! Map || decoded['data'] is! Map) {
      throw Exception('Invalid create response for $doctype.');
    }

    final payload = decoded['data'];
    return payload is Map<String, dynamic>
        ? payload
        : Map<String, dynamic>.from(payload as Map);
  }

  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    required String doctype,
    required String documentName,
    String? fieldname,
  }) async {
    await ensureLoggedIn();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/method/upload_file'),
    );
    request.headers[HttpHeaders.acceptHeader] = 'application/json';
    if (_cookies.isNotEmpty) {
      request.headers[HttpHeaders.cookieHeader] = _cookieHeader();
    }
    request.fields.addAll({
      'doctype': doctype,
      'docname': documentName,
      'is_private': '0',
      if (fieldname != null && fieldname.trim().isNotEmpty)
        'fieldname': fieldname.trim(),
    });
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = await _decodeJson(response.body);
    if (response.statusCode != 200) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }
    final message = decoded is Map ? decoded['message'] : null;
    if (message is Map<String, dynamic>) return message;
    if (message is Map) return Map<String, dynamic>.from(message);
    throw Exception('Invalid upload response.');
  }

  Future<List<int>> downloadPrintPdf({
    required String doctype,
    required String name,
    String? printFormat,
    bool noLetterhead = false,
  }) async {
    await ensureLoggedIn();

    final uri =
        Uri.parse(
          '$baseUrl/api/method/frappe.utils.print_format.download_pdf',
        ).replace(
          queryParameters: {
            'doctype': doctype,
            'name': name,
            if (printFormat?.trim().isNotEmpty == true)
              'format': printFormat!.trim(),
            'no_letterhead': noLetterhead ? '1' : '0',
          },
        );

    final response = await _getBytes(uri);
    if (response.statusCode != 200) {
      dynamic decoded;
      try {
        decoded = await _decodeJson(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }
    if (response.bodyBytes.isEmpty) {
      throw Exception('ERPNext tidak mengembalikan file PDF.');
    }
    final header = utf8.decode(
      response.bodyBytes.take(5).toList(),
      allowMalformed: true,
    );
    if (!header.startsWith('%PDF')) {
      throw Exception(
        'ERPNext tidak mengembalikan PDF. Pastikan Print Format tersedia.',
      );
    }
    return response.bodyBytes;
  }

  Future<String?> resolvePrintFormat(
    String doctype, {
    String? preferred,
  }) async {
    final wanted = preferred?.trim();
    try {
      final rows = await fetchResource(
        'Print Format',
        fields: const ['name'],
        filters: [
          ['doc_type', '=', doctype],
          ['disabled', '=', 0],
        ],
        limit: 50,
      );
      final names = [
        for (final row in rows)
          if ((row['name']?.toString().trim() ?? '').isNotEmpty)
            row['name'].toString().trim(),
      ];
      if (wanted != null && names.contains(wanted)) return wanted;
      for (final name in names) {
        if (name.toLowerCase().contains('struk')) return name;
      }
    } catch (_) {}
    return wanted;
  }

  Future<void> updateDocument(
    String doctype,
    String name,
    Map<String, dynamic> data,
  ) async {
    await ensureLoggedIn();

    final encodedDoctype = Uri.encodeComponent(doctype);
    final encodedName = Uri.encodeComponent(name);
    final uri = Uri.parse('$baseUrl/api/resource/$encodedDoctype/$encodedName');

    final result = await _sendJsonWithRelogin(
      () => _put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ),
      uri: uri,
    );
    final response = result.response;
    final decoded = result.decoded;

    if (response.statusCode != 200) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }
  }

  Future<dynamic> callMethod(
    String method, {
    Map<String, dynamic>? args,
  }) async {
    await ensureLoggedIn();

    final uri = Uri.parse('$baseUrl/api/method/$method');
    final result = await _sendJsonWithRelogin(
      () => _post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(args ?? {}),
      ),
      uri: uri,
    );
    final response = result.response;
    final decoded = result.decoded;

    if (response.statusCode != 200) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }

    if (decoded is Map && decoded['exc'] != null) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }

    if (decoded is Map) {
      return decoded['message'];
    }
    return decoded;
  }

  Future<Map<String, dynamic>> fetchSalesItemPricing({
    required String itemCode,
    required String customer,
    required String company,
    required String transactionDate,
    required double qty,
    String? warehouse,
    String? priceList,
    String? currency,
    String? customerGroup,
    String? uom,
    bool ignorePricingRule = false,
  }) async {
    final pricingArgs = <String, dynamic>{
      'doctype': 'Sales Order',
      'item_code': itemCode,
      'customer': customer,
      'company': company,
      'transaction_date': transactionDate,
      'conversion_rate': 1,
      'price_list_currency': currency,
      'plc_conversion_rate': 1,
      'qty': qty,
      'stock_qty': qty,
      'is_pos': 0,
      'ignore_pricing_rule': ignorePricingRule ? 1 : 0,
      if (warehouse != null && warehouse.trim().isNotEmpty)
        'warehouse': warehouse.trim(),
      if (priceList != null && priceList.trim().isNotEmpty)
        'price_list': priceList.trim(),
      if (priceList != null && priceList.trim().isNotEmpty)
        'selling_price_list': priceList.trim(),
      if (currency != null && currency.trim().isNotEmpty)
        'currency': currency.trim(),
      if (customerGroup != null && customerGroup.trim().isNotEmpty)
        'customer_group': customerGroup.trim(),
      if (uom != null && uom.trim().isNotEmpty) 'uom': uom.trim(),
    };

    final result = await callMethod(
      'erpnext.stock.get_item_details.get_item_details',
      args: {
        'args': jsonEncode(pricingArgs),
        'doc': jsonEncode({
          'doctype': 'Sales Order',
          'customer': customer,
          'company': company,
          'transaction_date': transactionDate,
          'currency': currency,
          'customer_group': customerGroup,
          'selling_price_list': priceList,
          'ignore_pricing_rule': ignorePricingRule ? 1 : 0,
        }),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('ERPNext tidak mengembalikan detail harga item.');
  }

  Future<dynamic> callDocumentMethod({
    required Map<String, dynamic> document,
    required String method,
  }) {
    return callMethod(
      'run_doc_method',
      args: {'docs': jsonEncode(document), 'method': method},
    );
  }

  Future<List<String>> fetchNamingSeries(String doctype) async {
    Object? settingsError;
    try {
      final settings = await fetchDocument(
        'Document Naming Settings',
        'Document Naming Settings',
      );
      final document = Map<String, dynamic>.from(settings)
        ..['transaction_type'] = doctype;
      final result = await callDocumentMethod(
        document: document,
        method: 'get_options',
      );
      final options = _splitOptions(result);
      if (options.isNotEmpty) return options;
    } catch (error) {
      settingsError = error;
    }

    try {
      final meta = await fetchDocument('DocType', doctype);
      final fields = meta['fields'];
      if (fields is List) {
        for (final field in fields) {
          if (field is! Map ||
              field['fieldname']?.toString() != 'naming_series') {
            continue;
          }
          final options = _splitOptions(field['options']);
          final defaultValue = field['default']?.toString().trim() ?? '';
          if (defaultValue.isNotEmpty && options.contains(defaultValue)) {
            return [
              defaultValue,
              ...options.where((option) => option != defaultValue),
            ];
          }
          if (options.isNotEmpty) return options;
        }
      }
    } catch (error) {
      settingsError ??= error;
    }

    throw Exception(
      'Naming series untuk $doctype tidak tersedia. ${settingsError ?? ''}',
    );
  }

  List<String> _splitOptions(dynamic raw) {
    final values = raw is List ? raw : raw?.toString().split('\n') ?? const [];
    final seen = <String>{};
    return values
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList();
  }

  Future<Map<String, dynamic>> submitDocument(
    String doctype,
    String name,
  ) async {
    final doc = await fetchDocument(doctype, name);
    final result = await callMethod('frappe.client.submit', args: {'doc': doc});
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return fetchDocument(doctype, name);
  }

  Future<Map<String, dynamic>> cancelDocument(
    String doctype,
    String name,
  ) async {
    final doc = await fetchDocument(doctype, name);
    final result = await callMethod('frappe.client.cancel', args: {'doc': doc});
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return fetchDocument(doctype, name);
  }

  Future<void> deleteDocument(String doctype, String name) async {
    await ensureLoggedIn();

    final encodedDoctype = Uri.encodeComponent(doctype);
    final encodedName = Uri.encodeComponent(name);
    final uri = Uri.parse('$baseUrl/api/resource/$encodedDoctype/$encodedName');

    final response = await _delete(uri);
    final decoded = response.body.isNotEmpty
        ? await _decodeJson(response.body)
        : null;

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception(_extractFrappeError(decoded, response.statusCode));
    }
  }

  Future<http.Response> _put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = _requestTimeout;
    try {
      final request = await httpClient.putUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (headers != null) {
        headers.forEach((key, value) {
          if (key.toLowerCase() == HttpHeaders.expectHeader.toLowerCase()) {
            return;
          }
          request.headers.set(key, value);
        });
      }
      if (_cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader());
      }
      request.headers.removeAll(HttpHeaders.expectHeader);

      if (body != null) {
        request.write(body.toString());
      }

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      _updateCookiesFromHeaders(response.headers);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      return http.Response(
        responseBody,
        response.statusCode,
        headers: responseHeaders,
        reasonPhrase: response.reasonPhrase,
      );
    } on TimeoutException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on SocketException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on HandshakeException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = _requestTimeout;
    try {
      final request = await httpClient.postUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (headers != null) {
        headers.forEach((key, value) {
          if (key.toLowerCase() == HttpHeaders.expectHeader.toLowerCase()) {
            return;
          }
          request.headers.set(key, value);
        });
      }
      if (_cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader());
      }
      request.headers.removeAll(HttpHeaders.expectHeader);

      if (body != null) {
        if (body is Map<String, String>) {
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/x-www-form-urlencoded',
          );
          request.write(Uri(queryParameters: body).query);
        } else {
          request.write(body.toString());
        }
      }

      final sentRequestHeaders = <String, String>{};
      request.headers.forEach((name, values) {
        sentRequestHeaders[name] = values.join(',');
      });

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      _updateCookiesFromHeaders(response.headers);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      if (response.statusCode >= 400) {
        _logHttpError(
          method: 'POST',
          uri: uri,
          requestHeaders: sentRequestHeaders,
          statusCode: response.statusCode,
          responseHeaders: responseHeaders,
          responseBody: responseBody,
        );
      }
      return http.Response(
        responseBody,
        response.statusCode,
        headers: responseHeaders,
        reasonPhrase: response.reasonPhrase,
      );
    } on TimeoutException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on SocketException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on HandshakeException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = _requestTimeout;
    try {
      final request = await httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (headers != null) {
        headers.forEach((key, value) {
          if (key.toLowerCase() == HttpHeaders.expectHeader.toLowerCase()) {
            return;
          }
          request.headers.set(key, value);
        });
      }
      if (_cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader());
      }
      request.headers.removeAll(HttpHeaders.expectHeader);

      final sentRequestHeaders = <String, String>{};
      request.headers.forEach((name, values) {
        sentRequestHeaders[name] = values.join(',');
      });

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      _updateCookiesFromHeaders(response.headers);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      if (response.statusCode >= 400) {
        _logHttpError(
          method: 'GET',
          uri: uri,
          requestHeaders: sentRequestHeaders,
          statusCode: response.statusCode,
          responseHeaders: responseHeaders,
          responseBody: responseBody,
        );
      }
      return http.Response(
        responseBody,
        response.statusCode,
        headers: responseHeaders,
        reasonPhrase: response.reasonPhrase,
      );
    } on TimeoutException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on SocketException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on HandshakeException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<http.Response> _getBytes(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = _requestTimeout;
    try {
      final request = await httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/pdf');
      if (headers != null) {
        headers.forEach((key, value) {
          if (key.toLowerCase() == HttpHeaders.expectHeader.toLowerCase()) {
            return;
          }
          request.headers.set(key, value);
        });
      }
      if (_cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader());
      }
      request.headers.removeAll(HttpHeaders.expectHeader);

      final sentRequestHeaders = <String, String>{};
      request.headers.forEach((name, values) {
        sentRequestHeaders[name] = values.join(',');
      });

      final response = await request.close().timeout(_requestTimeout);
      final responseBytes = await consolidateHttpClientResponseBytes(
        response,
      ).timeout(_requestTimeout);
      _updateCookiesFromHeaders(response.headers);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      if (response.statusCode >= 400) {
        _logHttpError(
          method: 'GET',
          uri: uri,
          requestHeaders: sentRequestHeaders,
          statusCode: response.statusCode,
          responseHeaders: responseHeaders,
          responseBody: utf8.decode(responseBytes, allowMalformed: true),
        );
      }
      return http.Response.bytes(
        responseBytes,
        response.statusCode,
        headers: responseHeaders,
        reasonPhrase: response.reasonPhrase,
      );
    } on TimeoutException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on SocketException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on HandshakeException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) async {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = _requestTimeout;
    try {
      final request = await httpClient.deleteUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (headers != null) {
        headers.forEach((key, value) {
          if (key.toLowerCase() == HttpHeaders.expectHeader.toLowerCase()) {
            return;
          }
          request.headers.set(key, value);
        });
      }
      if (_cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, _cookieHeader());
      }
      request.headers.removeAll(HttpHeaders.expectHeader);

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      _updateCookiesFromHeaders(response.headers);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      return http.Response(
        responseBody,
        response.statusCode,
        headers: responseHeaders,
        reasonPhrase: response.reasonPhrase,
      );
    } on TimeoutException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on SocketException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } on HandshakeException catch (error) {
      throw Exception(_friendlyNetworkError(error, uri));
    } finally {
      httpClient.close(force: true);
    }
  }

  String _friendlyNetworkError(Object error, Uri uri) {
    final host = uri.host.isEmpty ? 'ERPNext' : uri.host;
    final message = error.toString().toLowerCase();
    if (error is TimeoutException) {
      return 'Koneksi ke $host timeout. Periksa internet atau coba lagi.';
    }
    if (message.contains('failed host lookup') ||
        message.contains('no address associated') ||
        message.contains('nodename nor servname')) {
      return 'Site $host tidak bisa ditemukan. Periksa koneksi internet, DNS, atau kode perusahaan.';
    }
    if (error is HandshakeException) {
      return 'Koneksi SSL ke $host gagal. Periksa sertifikat HTTPS site ERPNext.';
    }
    return 'Tidak bisa terhubung ke $host. Periksa koneksi internet atau jaringan perangkat.';
  }

  void _updateCookiesFromHeaders(HttpHeaders headers) {
    headers.forEach((name, values) {
      if (name.toLowerCase() != 'set-cookie') return;
      for (final rawCookie in values) {
        final parts = rawCookie.split(RegExp(r', (?=[^;]+=)'));
        for (final part in parts) {
          final cookie = part.split(';').first.trim();
          final separatorIndex = cookie.indexOf('=');
          if (separatorIndex <= 0) continue;
          final key = cookie.substring(0, separatorIndex).trim();
          final value = cookie.substring(separatorIndex + 1).trim();
          if (key.isNotEmpty) {
            _cookies[key] = value;
          }
        }
      }
    });
  }

  String _cookieHeader() {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<_DecodedFrappeResponse> _sendJsonWithRelogin(
    Future<http.Response> Function() request, {
    required Uri uri,
  }) async {
    final response = await request();
    try {
      return _DecodedFrappeResponse(
        response: response,
        decoded: await _decodeJson(response.body),
      );
    } catch (error) {
      if (!_isHtmlResponseError(error) || !hasCredentials) rethrow;
      _cookies.clear();
      await login(username!, password!);
      final retry = await request();
      try {
        return _DecodedFrappeResponse(
          response: retry,
          decoded: await _decodeJson(retry.body),
        );
      } catch (retryError) {
        if (_isHtmlResponseError(retryError)) {
          throw Exception(
            'ERPNext mengembalikan halaman HTML untuk ${uri.path}. '
            'Status ${retry.statusCode}. Pastikan user punya API access dan permission DocType.',
          );
        }
        rethrow;
      }
    }
  }

  Future<dynamic> _decodeJson(String source) async {
    try {
      if (source.length < 50 * 1024) {
        return jsonDecode(source);
      }
      return compute(jsonDecode, source);
    } on FormatException {
      final trimmed = source.trimLeft().toLowerCase();
      if (trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html')) {
        throw Exception(
          'ERPNext mengembalikan halaman HTML, bukan data API. '
          'Periksa session login, permission DocType, dan endpoint ERPNext.',
        );
      }
      rethrow;
    }
  }

  bool _isHtmlResponseError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('mengembalikan halaman html') ||
        message.contains('returned html') ||
        message.contains('<!doctype html') ||
        message.contains('<html');
  }

  static String _extractFrappeError(dynamic decoded, int statusCode) {
    if (decoded is Map) {
      final exception = decoded['exception']?.toString();
      if (exception != null && exception.isNotEmpty) {
        return _friendlyFrappeMessage(exception, statusCode);
      }

      final exc = decoded['exc']?.toString();
      if (exc != null && exc.isNotEmpty) {
        return _friendlyFrappeMessage(exc, statusCode);
      }

      final message = decoded['message'];
      if (message != null) {
        return _friendlyFrappeMessage(message.toString(), statusCode);
      }

      final serverMessages = decoded['_server_messages']?.toString();
      if (serverMessages != null && serverMessages.isNotEmpty) {
        return _friendlyFrappeMessage(serverMessages, statusCode);
      }
    }

    return 'Frappe API error: $statusCode';
  }

  static String _friendlyFrappeMessage(String raw, int statusCode) {
    final parsed = _parseServerMessage(raw).trim();
    final message = parsed.isEmpty ? raw.trim() : parsed;
    final lower = message.toLowerCase();

    // Keep Query Report permission details — callers need to distinguish
    // Report roles vs Ref DocType "Report" permission.
    if (lower.contains("don't have access to report") ||
        lower.contains('dont have access to report') ||
        lower.contains('permission to get a report on')) {
      return _stripFrappeExceptionPrefix(message);
    }

    return ErpErrorMessage.fromFrappe(message, statusCode: statusCode);
  }

  static String _parseServerMessage(String raw) {
    dynamic value = raw;
    for (var depth = 0; depth < 3; depth++) {
      if (value is! String) break;
      final trimmed = value.trim();
      if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) break;
      try {
        value = jsonDecode(trimmed);
      } on FormatException {
        break;
      }
    }

    if (value is List) {
      final messages = value
          .map(_messageFromServerMessageItem)
          .where((message) => message.trim().isNotEmpty)
          .toList();
      if (messages.isNotEmpty) return messages.join('\n');
    }
    if (value is Map) {
      return _messageFromServerMessageItem(value);
    }
    return raw;
  }

  static String _messageFromServerMessageItem(dynamic item) {
    if (item is String) {
      final nested = _parseServerMessage(item);
      return nested == item ? item : nested;
    }
    if (item is Map) {
      final message = item['message'] ?? item['title'] ?? item['indicator'];
      return message?.toString() ?? '';
    }
    return item?.toString() ?? '';
  }

  static String _stripFrappeExceptionPrefix(String message) {
    final cleaned = message
        .replaceFirst(
          RegExp(r'^frappe\.exceptions\.[A-Za-z]+:\s*'),
          '',
        )
        .replaceFirst(RegExp(r'^[A-Za-z]*Error:\s*'), '')
        .trim();
    return cleaned.isEmpty ? message.trim() : cleaned;
  }

  void _logHttpError({
    required String method,
    required Uri uri,
    required Map<String, String> requestHeaders,
    required int statusCode,
    required Map<String, String> responseHeaders,
    required String responseBody,
  }) {
    developer.log(
      'FrappeService $method error for $uri\n'
      'Sent request headers: $requestHeaders\n'
      'Response status: $statusCode\n'
      'Response headers: $responseHeaders\n'
      'Response body: $responseBody',
      name: 'FrappeService',
    );
  }
}

class _DecodedFrappeResponse {
  final http.Response response;
  final dynamic decoded;

  const _DecodedFrappeResponse({required this.response, required this.decoded});
}
