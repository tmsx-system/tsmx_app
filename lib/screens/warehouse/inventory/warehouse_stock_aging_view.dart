import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../services/frappe_service.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_empty_state.dart';

/// Shows the ERP Custom HTML Block named Stock Ageing inside the Aging tab.
class WarehouseStockAgingView extends StatefulWidget {
  const WarehouseStockAgingView({super.key});

  @override
  State<WarehouseStockAgingView> createState() =>
      _WarehouseStockAgingViewState();
}

class _WarehouseStockAgingViewState extends State<WarehouseStockAgingView>
    with AutomaticKeepAliveClientMixin {
  static const _blockNames = ['Stock Ageing', 'Stock Aging'];

  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _controller = null;
    });
    try {
      final frappe = context.read<WarehouseStockState>().frappeService;
      await frappe.ensureLoggedIn();
      final block = await _loadBlock(frappe);
      final html = _field(block, const ['html', 'private_html']);
      final style = _field(block, const ['style']);
      final script = _field(block, const ['script']);
      if (html.trim().isEmpty && script.trim().isEmpty) {
        throw Exception('Custom HTML Block Stock Ageing belum memiliki isi.');
      }
      var csrf = '';
      try {
        final csrfRaw = await frappe.getMethod(
          'frappe.sessions.get_csrf_token',
        );
        csrf = csrfRaw?.toString() ?? '';
      } catch (_) {
        csrf = '';
      }
      final baseUrl = frappe.baseUrl.replaceAll(RegExp(r'/+$'), '');
      await _applySessionCookies(baseUrl, frappe.sessionCookieHeader);
      if (!mounted) return;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(AppColors.background)
        ..loadHtmlString(
          _document(
            baseUrl: baseUrl,
            csrf: csrf,
            html: html,
            style: style,
            script: script,
          ),
          baseUrl: '$baseUrl/',
        );
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      final parsed = captureErpError(context, error);
      setState(() {
        _error = parsed.contains('Sesi login')
            ? 'Custom HTML Block Stock Ageing belum bisa dibaca oleh role ini. '
                  'Beri izin Read pada DocType Custom HTML Block, lalu muat ulang.'
            : parsed;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _loadBlock(FrappeService frappe) async {
    Object? lastError;
    for (final name in _blockNames) {
      try {
        return await frappe.fetchDocument('Custom HTML Block', name);
      } catch (error) {
        lastError = error;
      }
      try {
        final message = await frappe.getMethod(
          'frappe.client.get',
          query: {'doctype': 'Custom HTML Block', 'name': name},
        );
        if (message is Map) {
          return Map<String, dynamic>.from(message);
        }
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('Custom HTML Block Stock Ageing kosong.');
  }

  String _field(Map<String, dynamic> doc, List<String> keys) {
    for (final key in keys) {
      final value = doc[key]?.toString() ?? '';
      if (value.trim().isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _applySessionCookies(String baseUrl, String? header) async {
    if (header == null || header.trim().isEmpty) return;
    final host = Uri.parse(baseUrl).host;
    if (host.isEmpty) return;
    final manager = WebViewCookieManager();
    for (final part in header.split(';')) {
      final cookie = part.trim();
      final separator = cookie.indexOf('=');
      if (separator <= 0) continue;
      await manager.setCookie(
        WebViewCookie(
          name: cookie.substring(0, separator).trim(),
          value: cookie.substring(separator + 1).trim(),
          domain: host,
          path: '/',
        ),
      );
    }
  }

  String _document({
    required String baseUrl,
    required String csrf,
    required String html,
    required String style,
    required String script,
  }) {
    final safeScript = script.replaceAll('</script', '<\\/script');
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<base href="${htmlEscape.convert('$baseUrl/')}">
<style>
  html, body { margin: 0; background: #f4f7f5; }
  body { padding: 12px; font-family: sans-serif; }
  $style
</style>
</head>
<body>
<div id="stock-ageing-root">
$html
</div>
<script>
  window.root_element = document.getElementById('stock-ageing-root');
</script>
<script>
(function () {
  const baseUrl = ${jsonEncode(baseUrl)};
  const csrf = ${jsonEncode(csrf)};
  function callApi(opts) {
    const method = typeof opts === 'string' ? opts : (opts && opts.method) || '';
    const args = (opts && opts.args) || {};
    return fetch(baseUrl + '/api/method/' + method, {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Frappe-CSRF-Token': csrf
      },
      body: JSON.stringify(args)
    }).then(function (response) {
      return response.json().then(function (data) {
        if (!response.ok || (data && data.exc)) {
          if (opts && typeof opts.error === 'function') opts.error(data);
          throw data;
        }
        if (opts && typeof opts.callback === 'function') opts.callback(data);
        return data;
      });
    });
  }
  window.csrf_token = csrf;
  window.frappe = window.frappe || {};
  frappe.csrf_token = csrf;
  frappe.boot = frappe.boot || { csrf_token: csrf };
  frappe.call = callApi;
  frappe.xcall = function (method, args) { return callApi({ method: method, args: args }); };
  frappe.ready = function (fn) { if (typeof fn === 'function') fn(); };
  frappe.msgprint = function (message) { console.log(message); };
  frappe.throw = function (message) { throw new Error(String(message && message.message || message)); };
  frappe.db = frappe.db || {};
  frappe.db.get_list = function (doctype, args) {
    return callApi({ method: 'frappe.client.get_list', args: Object.assign({ doctype: doctype }, args || {}) });
  };
  frappe.db.get_value = function (doctype, name, fieldname) {
    return callApi({
      method: 'frappe.client.get_value',
      args: { doctype: doctype, filters: name, fieldname: fieldname }
    });
  };
})();
</script>
<script>
$safeScript
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            ErpEmptyState(
              title: 'Stock Ageing tidak tampil',
              message: _error!,
              icon: Icons.hourglass_bottom_rounded,
            ),
          ],
        ),
      );
    }
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return WebViewWidget(controller: controller);
  }
}
