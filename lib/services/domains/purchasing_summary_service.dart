import '../../models/erp_summary.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/num_parse.dart';

class PurchasingSummaryResult {
  const PurchasingSummaryResult({
    required this.purchaseOrderSummary,
    required this.purchaseReceiptSummary,
    required this.purchaseInvoiceSummary,
    required this.purchaseOrderTrendPoints,
    required this.purchaseReceiptTrendPoints,
    required this.purchaseInvoiceTrendPoints,
    required this.materialRequestTrendPoints,
  });

  final DocumentSummary purchaseOrderSummary;
  final DocumentSummary purchaseReceiptSummary;
  final DocumentSummary purchaseInvoiceSummary;
  final List<DocumentTrendPoint> purchaseOrderTrendPoints;
  final List<DocumentTrendPoint> purchaseReceiptTrendPoints;
  final List<DocumentTrendPoint> purchaseInvoiceTrendPoints;
  final List<DocumentTrendPoint> materialRequestTrendPoints;
}

class PurchasingSummaryService {
  const PurchasingSummaryService({required this.frappe});

  final FrappeService frappe;

  Future<PurchasingSummaryResult> fetch({
    required int year,
    required int month,
    required DateTime from,
    required DateTime to,
    required String company,
    required String supplierType,
  }) async {
    await frappe.ensureLoggedIn();

    final sections = await Future.wait([
      _fetchPurchaseAnalytics(
        docType: 'Purchase Order',
        year: year,
        month: month,
        from: from,
        to: to,
        company: company,
        supplierType: supplierType,
      ),
      _fetchPurchaseAnalyticsOrEmpty(
        docType: 'Purchase Receipt',
        year: year,
        month: month,
        from: from,
        to: to,
        company: company,
        supplierType: supplierType,
      ),
      _fetchPurchaseAnalyticsOrEmpty(
        docType: 'Purchase Invoice',
        year: year,
        month: month,
        from: from,
        to: to,
        company: company,
        supplierType: supplierType,
      ),
      _fetchPurchaseAnalyticsOrEmpty(
        docType: 'Material Request',
        year: year,
        month: month,
        from: from,
        to: to,
        company: company,
        supplierType: supplierType,
      ),
    ]);

    final purchaseOrder = sections[0];
    final purchaseReceipt = sections[1];
    final purchaseInvoice = sections[2];
    final materialRequest = sections[3];
    return PurchasingSummaryResult(
      purchaseOrderSummary: purchaseOrder.summary,
      purchaseReceiptSummary: purchaseReceipt.summary,
      purchaseInvoiceSummary: purchaseInvoice.summary,
      purchaseOrderTrendPoints: purchaseOrder.trend,
      purchaseReceiptTrendPoints: purchaseReceipt.trend,
      purchaseInvoiceTrendPoints: purchaseInvoice.trend,
      materialRequestTrendPoints: materialRequest.trend,
    );
  }

  Future<_AnalyticsSection> _fetchPurchaseAnalyticsOrEmpty({
    required String docType,
    required int year,
    required int month,
    required DateTime from,
    required DateTime to,
    required String company,
    required String supplierType,
  }) async {
    try {
      return await _fetchPurchaseAnalytics(
        docType: docType,
        year: year,
        month: month,
        from: from,
        to: to,
        company: company,
        supplierType: supplierType,
      );
    } catch (_) {
      return _AnalyticsSection(
        summary: const DocumentSummary(),
        trend: _emptyAnalyticsTrend(year, month),
      );
    }
  }

  Future<_AnalyticsSection> _fetchPurchaseAnalytics({
    required String docType,
    required int year,
    required int month,
    required DateTime from,
    required DateTime to,
    required String company,
    required String supplierType,
  }) async {
    final selectedSupplierType = supplierType.trim();
    final response = await frappe.callMethod(
      'frappe.desk.query_report.run',
      args: {
        'report_name': 'Purchase Analytics',
        'filters': {
          'tree_type': 'Supplier',
          'doc_type': docType,
          'document_type': docType,
          'based_on': docType,
          'value_quantity': 'Value',
          'range': month == 0 ? 'Monthly' : 'Weekly',
          'from_date': DateRangePresets.toFrappeDate(from),
          'to_date': DateRangePresets.toFrappeDate(to),
          if (company.trim().isNotEmpty) 'company': company.trim(),
          if (selectedSupplierType.isNotEmpty &&
              selectedSupplierType.toLowerCase() != 'all')
            'supplier_type': selectedSupplierType,
          'show_aggregate_value_from_subsidiary_companies': 0,
        },
        'ignore_prepared_report': true,
        'are_default_filters': false,
      },
    );
    return _analyticsSectionFromQueryReport(response, year, month);
  }

  _AnalyticsSection _analyticsSectionFromQueryReport(
    dynamic response,
    int year,
    int month,
  ) {
    final report = _queryReportPayload(response);
    if (report == null) {
      return _AnalyticsSection(
        summary: const DocumentSummary(),
        trend: _emptyAnalyticsTrend(year, month),
      );
    }

    final columns = _queryReportColumns(report['columns']);
    final rows = _queryReportRows(report['result'] ?? report['data']);
    var periodColumns = _queryReportPeriodColumns(columns, month);
    if (periodColumns.isEmpty) {
      periodColumns = _queryReportPeriodColumnsFromRows(rows, month);
    }
    if (periodColumns.isEmpty) {
      return _AnalyticsSection(
        summary: const DocumentSummary(),
        trend: _emptyAnalyticsTrend(year, month),
      );
    }

    final trend = _emptyAnalyticsTrend(
      year,
      month,
      periodColumns: periodColumns,
    );
    final totalRowTrend = _emptyAnalyticsTrend(
      year,
      month,
      periodColumns: periodColumns,
    );
    var totalValue = 0.0;
    var totalRowValue = 0.0;
    var hasTotalRow = false;
    var rowCount = 0;

    for (final row in rows) {
      final mapped = _queryReportRowMap(row, columns);
      final isTotalRow = _isQueryReportTotalRow(mapped);
      var hasValue = false;
      for (final entry in periodColumns.entries) {
        final value = NumParse.asDouble(
          mapped[_queryReportPeriodColumnField(entry.value)],
        );
        if (isTotalRow) {
          hasTotalRow = true;
          totalRowValue += value;
          totalRowTrend[entry.key] = DocumentTrendPoint(
            label: totalRowTrend[entry.key].label,
            value: value,
            documentCount: value == 0 ? 0 : 1,
          );
          continue;
        }
        if (value == 0) continue;
        totalValue += value;
        hasValue = true;
        trend[entry.key] = trend[entry.key].add(value);
      }
      if (!isTotalRow && hasValue) rowCount++;
    }

    return _AnalyticsSection(
      summary: DocumentSummary(
        totalValue: hasTotalRow ? totalRowValue : totalValue,
        documentCount: rowCount,
      ),
      trend: hasTotalRow ? totalRowTrend : trend,
    );
  }

  Map<String, dynamic>? _queryReportPayload(dynamic response) {
    if (response is! Map) return null;
    final map = Map<String, dynamic>.from(response);
    final message = map['message'];
    if (message is Map) return Map<String, dynamic>.from(message);
    return map;
  }

  List<Map<String, dynamic>> _queryReportColumns(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((column) {
      if (column is String) {
        return {'label': column, 'fieldname': column};
      }
      if (column is Map) return Map<String, dynamic>.from(column);
      return <String, dynamic>{};
    }).toList();
  }

  List<dynamic> _queryReportRows(dynamic raw) => raw is List ? raw : const [];

  Map<String, dynamic> _queryReportRowMap(
    dynamic row,
    List<Map<String, dynamic>> columns,
  ) {
    if (row is Map) return Map<String, dynamic>.from(row);
    if (row is! List) return const {};
    final mapped = <String, dynamic>{};
    for (var i = 0; i < row.length && i < columns.length; i++) {
      final fieldname =
          columns[i]['fieldname']?.toString() ??
          columns[i]['field']?.toString() ??
          columns[i]['label']?.toString() ??
          '';
      if (fieldname.isEmpty) continue;
      mapped[fieldname] = row[i];
    }
    return mapped;
  }

  Map<int, String> _queryReportPeriodColumns(
    List<Map<String, dynamic>> columns,
    int month,
  ) {
    final result = <int, String>{};
    for (final column in columns) {
      final fieldname =
          column['fieldname']?.toString() ??
          column['field']?.toString() ??
          column['label']?.toString() ??
          '';
      if (fieldname.isEmpty) continue;
      final rawLabel = column['label']?.toString() ?? fieldname;
      final label = rawLabel.toLowerCase();
      final index = month > 0 && RegExp(r'(week|minggu)\s*\d+').hasMatch(label)
          ? result.length
          : _queryReportPeriodIndex(label, month);
      if (index == null) continue;
      result[index] = _queryReportPeriodColumnKey(fieldname, rawLabel);
    }
    return result;
  }

  Map<int, String> _queryReportPeriodColumnsFromRows(
    List<dynamic> rows,
    int month,
  ) {
    final result = <int, String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      for (final key in row.keys) {
        final fieldname = key.toString();
        if (fieldname.trim().isEmpty) continue;
        final label = fieldname.toLowerCase();
        final index =
            month > 0 && RegExp(r'(week|minggu)\s*\d+').hasMatch(label)
            ? result.length
            : _queryReportPeriodIndex(label, month);
        if (index == null) continue;
        result[index] = _queryReportPeriodColumnKey(fieldname, fieldname);
      }
      if (result.isNotEmpty) break;
    }
    return result;
  }

  String _queryReportPeriodColumnKey(String fieldname, String label) {
    return '$fieldname\u001f$label';
  }

  String _queryReportPeriodColumnField(String value) {
    return value.split('\u001f').first;
  }

  String _queryReportPeriodColumnLabel(String value) {
    final parts = value.split('\u001f');
    return parts.length > 1 ? parts.sublist(1).join('\u001f') : value;
  }

  int? _queryReportPeriodIndex(String label, int month) {
    if (month == 0) {
      const aliases = [
        ['jan'],
        ['feb'],
        ['mar'],
        ['apr'],
        ['may', 'mei'],
        ['jun'],
        ['jul'],
        ['aug', 'agu'],
        ['sep'],
        ['oct', 'okt'],
        ['nov'],
        ['dec', 'des'],
      ];
      for (var i = 0; i < aliases.length; i++) {
        if (aliases[i].any(label.contains)) return i;
      }
      return null;
    }

    final match = RegExp(r'(week|minggu)\s*(\d+)').firstMatch(label);
    if (match != null) {
      final week = int.tryParse(match.group(2) ?? '');
      if (week != null) return (week - 1).clamp(0, 3);
    }

    final date = _queryReportPeriodDate(label);
    if (date != null && date.month == month) {
      return ((date.day - 1) ~/ 7).clamp(0, 3);
    }
    return null;
  }

  DateTime? _queryReportPeriodDate(String label) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[_]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final iso = RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
    ).firstMatch(normalized);
    if (iso != null) {
      return DateTime.tryParse(
        '${iso.group(1)!}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}',
      );
    }

    final numeric = RegExp(
      r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})',
    ).firstMatch(normalized);
    if (numeric != null) {
      return DateTime.tryParse(
        '${numeric.group(3)!}-${numeric.group(2)!.padLeft(2, '0')}-${numeric.group(1)!.padLeft(2, '0')}',
      );
    }

    final named = RegExp(
      r'(\d{1,2})\s+(jan|feb|mar|apr|may|mei|jun|jul|aug|agu|sep|oct|okt|nov|dec|des)\w*\s+(\d{4})',
    ).firstMatch(normalized);
    if (named == null) return null;
    final month = _monthAliasNumber(named.group(2)!);
    if (month == null) return null;
    return DateTime.tryParse(
      '${named.group(3)!}-${month.toString().padLeft(2, '0')}-${named.group(1)!.padLeft(2, '0')}',
    );
  }

  int? _monthAliasNumber(String raw) {
    final value = raw.toLowerCase();
    const aliases = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'mei': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'agu': 8,
      'sep': 9,
      'oct': 10,
      'okt': 10,
      'nov': 11,
      'dec': 12,
      'des': 12,
    };
    final key = value.length <= 3 ? value : value.substring(0, 3);
    return aliases[key];
  }

  List<DocumentTrendPoint> _emptyAnalyticsTrend(
    int year,
    int month, {
    Map<int, String>? periodColumns,
  }) {
    if (month > 0 && periodColumns != null && periodColumns.isNotEmpty) {
      final entries = periodColumns.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return [
        for (var i = 0; i < entries.length; i++)
          DocumentTrendPoint(
            label: _weeklyReportLabel(
              _queryReportPeriodColumnLabel(entries[i].value),
              i,
            ),
          ),
      ];
    }

    if (month == 0) {
      const labels = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return [for (final label in labels) DocumentTrendPoint(label: label)];
    }

    return _emptyWeeklyTrendPoints(year, month);
  }

  List<DocumentTrendPoint> _emptyWeeklyTrendPoints(int year, int month) {
    if (month <= 0) return const [];
    final lastDay = DateTime(year, month + 1, 0).day;
    final weeks = <int>{};
    for (var day = 1; day <= lastDay; day++) {
      weeks.add(_isoWeekNumber(DateTime(year, month, day)));
    }
    final sortedWeeks = weeks.toList()..sort();
    return [
      for (final week in sortedWeeks) DocumentTrendPoint(label: 'Minggu $week'),
    ];
  }

  String _weeklyReportLabel(String rawLabel, int fallbackIndex) {
    final normalized = rawLabel
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final match = RegExp(r'(week|minggu)\s*(\d+)').firstMatch(normalized);
    if (match != null) return 'Minggu ${match.group(2)}';
    final date = _queryReportPeriodDate(rawLabel);
    if (date != null) return 'Minggu ${_isoWeekNumber(date)}';
    return rawLabel.trim().isEmpty ? 'Minggu ${fallbackIndex + 1}' : rawLabel;
  }

  int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    return 1 + ((thursday.difference(firstThursday).inDays) ~/ 7);
  }

  bool _isQueryReportTotalRow(Map<String, dynamic> row) {
    if (row.isEmpty) return false;
    return row.values.any((value) {
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text == 'total' || text == 'total (all)';
    });
  }
}

class _AnalyticsSection {
  const _AnalyticsSection({required this.summary, required this.trend});

  final DocumentSummary summary;
  final List<DocumentTrendPoint> trend;
}
