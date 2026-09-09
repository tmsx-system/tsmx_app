import '../../models/erp_summary.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import 'summary_trend_helpers.dart';

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

  static const int _pageSize = 500;

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
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds(supplierType);
    final purchaseOrder = await _fetchDocumentSummary(
      doctype: 'Purchase Order',
      dateField: 'transaction_date',
      fields: const [
        'name',
        'base_net_total',
        'net_total',
        'grand_total',
        'status',
        'docstatus',
        'transaction_date',
        'supplier',
      ],
      year: year,
      month: month,
      from: from,
      to: to,
      company: company,
      supplierIds: supplierTypeIds,
      isActiveRow: _isActivePurchaseOrderTrendRow,
      valueOf: _buyingAnalyticsValue,
    );
    final purchaseReceipt = await _fetchDocumentSummary(
      doctype: 'Purchase Receipt',
      dateField: 'posting_date',
      fields: const [
        'name',
        'supplier',
        'grand_total',
        'status',
        'docstatus',
        'posting_date',
      ],
      year: year,
      month: month,
      from: from,
      to: to,
      company: company,
      supplierIds: supplierTypeIds,
      isActiveRow: _isActiveBuyingTrendRow,
      valueOf: (row) => NumParse.asDouble(row['grand_total']),
    );
    final purchaseInvoice = await _fetchDocumentSummary(
      doctype: 'Purchase Invoice',
      dateField: 'posting_date',
      fields: const [
        'name',
        'supplier',
        'grand_total',
        'status',
        'docstatus',
        'posting_date',
      ],
      year: year,
      month: month,
      from: from,
      to: to,
      company: company,
      supplierIds: supplierTypeIds,
      isActiveRow: _isActiveBuyingTrendRow,
      valueOf: (row) => NumParse.asDouble(row['grand_total']),
    );
    final materialRequestTrend = SummaryTrendHelpers.emptyTrendPoints(
      year,
      month,
    );
    await _forEachResourcePage(
      doctype: 'Material Request',
      fields: const [
        'name',
        'total_qty',
        'status',
        'docstatus',
        'transaction_date',
      ],
      filters: [
        ..._buyingPeriodFilters(
          'transaction_date',
          from: from,
          to: to,
          company: company,
        ),
        ['docstatus', '!=', 2],
      ],
      onRow: (row) {
        if (!_isActiveBuyingTrendRow(row)) return;
        final qty = NumParse.asDouble(row['total_qty']);
        SummaryTrendHelpers.addTrendPoint(
          materialRequestTrend,
          year: year,
          month: month,
          dateRaw: row['transaction_date'],
          amount: qty <= 0 ? 1 : qty,
        );
      },
    );

    return PurchasingSummaryResult(
      purchaseOrderSummary: purchaseOrder.summary,
      purchaseReceiptSummary: purchaseReceipt.summary,
      purchaseInvoiceSummary: purchaseInvoice.summary,
      purchaseOrderTrendPoints: purchaseOrder.trend,
      purchaseReceiptTrendPoints: purchaseReceipt.trend,
      purchaseInvoiceTrendPoints: purchaseInvoice.trend,
      materialRequestTrendPoints: materialRequestTrend,
    );
  }

  Future<_SummarySection> _fetchDocumentSummary({
    required String doctype,
    required String dateField,
    required List<String> fields,
    required int year,
    required int month,
    required DateTime from,
    required DateTime to,
    required String company,
    required List<String>? supplierIds,
    required bool Function(Map<String, dynamic> row) isActiveRow,
    required double Function(Map<String, dynamic> row) valueOf,
  }) async {
    final trend = SummaryTrendHelpers.emptyTrendPoints(year, month);
    var totalValue = 0.0;
    var documentCount = 0;
    await _forEachResourcePage(
      doctype: doctype,
      fields: fields,
      filters: [
        ..._buyingPeriodFilters(
          dateField,
          from: from,
          to: to,
          company: company,
        ),
        ['docstatus', '!=', 2],
      ],
      onRow: (row) {
        if (!_matchesBuyingSupplierType(row, supplierIds)) return;
        if (!isActiveRow(row)) return;
        final value = valueOf(row);
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

  List<List<dynamic>> _buyingPeriodFilters(
    String dateField, {
    required DateTime from,
    required DateTime to,
    required String company,
  }) {
    return [
      [dateField, '>=', DateRangePresets.toFrappeDate(from)],
      [dateField, '<=', DateRangePresets.toFrappeDate(to)],
      ..._companyScopeFilters(company),
    ];
  }

  List<List<dynamic>> _companyScopeFilters(String selectedCompany) {
    final selected = selectedCompany.trim();
    if (selected.isEmpty) return const [];
    return [
      ['company', '=', selected],
    ];
  }

  Future<List<String>?> _buyingSupplierTypeSupplierIds(
    String supplierType,
  ) async {
    final type = supplierType.trim().toLowerCase();
    if (type.isEmpty || type == 'all') return null;

    final internal = type == 'internal';
    try {
      final rows = await walkFrappePages(
        pageSize: _pageSize,
        fetchPage: (start, limit) => frappe.fetchResource(
          'Supplier',
          fields: const ['name', 'is_internal_supplier'],
          limit: limit,
          limitStart: start,
        ),
      );
      return rows
          .where(
            (row) =>
                NumParse.asInt(row['is_internal_supplier']) ==
                (internal ? 1 : 0),
          )
          .map((row) => row['name']?.toString() ?? '')
          .where((name) => name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  bool _matchesBuyingSupplierType(
    Map<String, dynamic> row,
    List<String>? supplierIds,
  ) {
    if (supplierIds == null) return true;
    if (supplierIds.isEmpty) return false;
    return supplierIds.contains(row['supplier']?.toString() ?? '');
  }

  bool _isActivePurchaseOrderTrendRow(Map<String, dynamic> row) {
    final docstatus = NumParse.asInt(row['docstatus']);
    if (docstatus != 1) return false;

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    return status == 'to receive and bill' ||
        status == 'to receive and to bill' ||
        status == 'to bill' ||
        status == 'to receive' ||
        status == 'completed';
  }

  bool _isActiveBuyingTrendRow(Map<String, dynamic> row) {
    final docstatus = NumParse.asInt(row['docstatus']);
    if (docstatus != 1) return false;

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'draft' || status == 'cancelled') return false;
    if (status.contains('return')) return false;

    return true;
  }

  double _buyingAnalyticsValue(Map<String, dynamic> row) {
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
      fetchPage: (start, limit) => frappe.fetchResource(
        doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        filters: filters,
      ),
      onRow: onRow,
    );
  }
}

class _SummarySection {
  const _SummarySection({required this.summary, required this.trend});

  final DocumentSummary summary;
  final List<DocumentTrendPoint> trend;
}
