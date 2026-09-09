import '../../models/erp_summary.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import 'summary_trend_helpers.dart';

class SellingSummaryResult {
  const SellingSummaryResult({
    required this.salesOrderSummary,
    required this.deliveryNoteSummary,
    required this.salesInvoiceSummary,
    required this.salesOrderTrendPoints,
    required this.deliveryNoteTrendPoints,
    required this.salesInvoiceTrendPoints,
  });

  final DocumentSummary salesOrderSummary;
  final DocumentSummary deliveryNoteSummary;
  final DocumentSummary salesInvoiceSummary;
  final List<DocumentTrendPoint> salesOrderTrendPoints;
  final List<DocumentTrendPoint> deliveryNoteTrendPoints;
  final List<DocumentTrendPoint> salesInvoiceTrendPoints;
}

class SellingSummaryService {
  const SellingSummaryService({required this.frappe});

  static const int _pageSize = 500;

  final FrappeService frappe;

  Future<SellingSummaryResult> fetch({
    required int year,
    required int month,
    required DateTime from,
    required DateTime to,
    required String company,
    required String customerType,
    required bool shouldScopeSalesData,
    required Future<String?> Function() resolveCurrentSalesIdentity,
    required String? salesIdentityError,
  }) async {
    await frappe.ensureLoggedIn();
    final salesScopeFilters = await _salesDocumentScopeFilters(
      shouldScopeSalesData: shouldScopeSalesData,
      resolveCurrentSalesIdentity: resolveCurrentSalesIdentity,
      salesIdentityError: salesIdentityError,
    );
    final sales = await _fetchDocumentSummary(
      doctype: 'Sales Order',
      dateField: 'transaction_date',
      year: year,
      month: month,
      from: from,
      to: to,
      company: company,
      customerType: customerType,
      shouldScopeSalesData: shouldScopeSalesData,
      scopeFilters: salesScopeFilters,
    );
    final delivery = await _fetchDocumentSummary(
      doctype: 'Delivery Note',
      dateField: 'posting_date',
      year: year,
      month: month,
      from: from,
      to: to,
      company: company,
      customerType: customerType,
      shouldScopeSalesData: shouldScopeSalesData,
      scopeFilters: salesScopeFilters,
    );
    final invoice = await _fetchDocumentSummary(
      doctype: 'Sales Invoice',
      dateField: 'posting_date',
      year: year,
      month: month,
      from: from,
      to: to,
      company: company,
      customerType: customerType,
      shouldScopeSalesData: shouldScopeSalesData,
      scopeFilters: salesScopeFilters,
    );

    return SellingSummaryResult(
      salesOrderSummary: sales.summary,
      deliveryNoteSummary: delivery.summary,
      salesInvoiceSummary: invoice.summary,
      salesOrderTrendPoints: sales.trend,
      deliveryNoteTrendPoints: delivery.trend,
      salesInvoiceTrendPoints: invoice.trend,
    );
  }

  Future<_SummarySection> _fetchDocumentSummary({
    required String doctype,
    required String dateField,
    required int year,
    required int month,
    required DateTime from,
    required DateTime to,
    required String company,
    required String customerType,
    required bool shouldScopeSalesData,
    required List<List<dynamic>> scopeFilters,
  }) async {
    final trend = SummaryTrendHelpers.emptyTrendPoints(year, month);
    var totalValue = 0.0;
    var documentCount = 0;
    await _forEachResourcePage(
      doctype: doctype,
      fields: [
        'name',
        'base_net_total',
        'net_total',
        'grand_total',
        dateField,
        'customer',
        'status',
        'docstatus',
      ],
      filters: [
        ..._sellingDocumentFilters(
          dateField,
          from: from,
          to: to,
          company: company,
          customerType: customerType,
          shouldScopeSalesData: shouldScopeSalesData,
        ),
        ...scopeFilters,
      ],
      onRow: (row) {
        if (!_isActiveSellingTrendRow(row)) return;
        final value = _sellingAnalyticsValue(row);
        totalValue += value;
        documentCount += 1;
        SummaryTrendHelpers.addTrendPoint(
          trend,
          year: year,
          month: month,
          dateRaw: row[dateField],
          amount: value,
        );
      },
    );
    return _SummarySection(
      summary: DocumentSummary(
        totalValue: totalValue,
        documentCount: documentCount,
      ),
      trend: trend,
    );
  }

  List<List<dynamic>> _sellingDocumentFilters(
    String dateField, {
    required DateTime from,
    required DateTime to,
    required String company,
    required String customerType,
    required bool shouldScopeSalesData,
  }) {
    final filters = <List<dynamic>>[
      [dateField, '>=', DateRangePresets.toFrappeDate(from)],
      [dateField, '<=', DateRangePresets.toFrappeDate(to)],
      ..._companyScopeFilters(company),
    ];
    final parentSalesPerson = _selectedSellingParentSalesPerson(
      customerType: customerType,
      shouldScopeSalesData: shouldScopeSalesData,
    );
    if (parentSalesPerson != null) {
      filters.add(['parent_sales_person', '=', parentSalesPerson]);
    }
    return filters;
  }

  Future<List<List<dynamic>>> _salesDocumentScopeFilters({
    required bool shouldScopeSalesData,
    required Future<String?> Function() resolveCurrentSalesIdentity,
    required String? salesIdentityError,
  }) async {
    if (!shouldScopeSalesData) return const [];
    final salesPerson = (await resolveCurrentSalesIdentity())?.trim() ?? '';
    if (salesPerson.isEmpty) {
      throw Exception(
        salesIdentityError ?? 'Sales Person user login belum tersedia.',
      );
    }
    return [
      ['Sales Team', 'sales_person', '=', salesPerson],
    ];
  }

  String? _selectedSellingParentSalesPerson({
    required String customerType,
    required bool shouldScopeSalesData,
  }) {
    if (shouldScopeSalesData) return null;
    final group = customerType.trim();
    if (group.isEmpty || group.toLowerCase() == 'all') return null;
    return group;
  }

  List<List<dynamic>> _companyScopeFilters(String selectedCompany) {
    final selected = selectedCompany.trim();
    if (selected.isEmpty) return const [];
    return [
      ['company', '=', selected],
    ];
  }

  bool _isActiveSellingTrendRow(Map<String, dynamic> row) {
    final docstatus = NumParse.asInt(row['docstatus']);
    if (docstatus != 1) return false;

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'draft' || status == 'cancelled') return false;
    if (status == 'return') return false;

    return true;
  }

  double _sellingAnalyticsValue(Map<String, dynamic> row) {
    final baseNetTotal = NumParse.asDouble(row['base_net_total']);
    if (baseNetTotal != 0) return baseNetTotal;
    final netTotal = NumParse.asDouble(row['net_total']);
    if (netTotal != 0) return netTotal;
    return NumParse.asDouble(row['grand_total']);
  }

  Future<void> _forEachResourcePage({
    required String doctype,
    required List<String> fields,
    required List<List<dynamic>> filters,
    required void Function(Map<String, dynamic> row) onRow,
  }) {
    return walkFrappePages(
      pageSize: _pageSize,
      fetchPage: (start, limit) => _fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        filters: filters,
      ),
      onRow: onRow,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchResourceWithFieldFallback({
    required String doctype,
    required List<String> fields,
    required int limit,
    required int limitStart,
    required List<List<dynamic>> filters,
  }) async {
    var remainingFields = List<String>.from(fields);
    while (remainingFields.isNotEmpty) {
      try {
        if (_usesSalesTeamChildFilter(filters)) {
          return frappe.fetchReportView(
            doctype,
            fields: remainingFields,
            limit: limit,
            limitStart: limitStart,
            filters: filters,
          );
        }
        return await frappe.fetchResource(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          filters: filters,
        );
      } catch (error) {
        final badField = RegExp(
          r'Field not permitted in query:\s*([a-zA-Z0-9_]+)',
        ).firstMatch(error.toString())?.group(1);
        if (badField != null && remainingFields.contains(badField)) {
          remainingFields.remove(badField);
          continue;
        }
        rethrow;
      }
    }
    return const [];
  }

  bool _usesSalesTeamChildFilter(List<List<dynamic>> filters) {
    return filters.any((filter) {
      if (filter.length < 4) return false;
      if (filter.first.toString().trim() != 'Sales Team') return false;
      final field = filter[1].toString().trim();
      return field == 'parent_sales_person' || field == 'sales_person';
    });
  }
}

class _SummarySection {
  const _SummarySection({required this.summary, required this.trend});

  final DocumentSummary summary;
  final List<DocumentTrendPoint> trend;
}
