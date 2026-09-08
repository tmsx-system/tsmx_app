import '../../models/erp_summary.dart';
import '../../models/purchase_invoice.dart';
import '../../models/warehouse_info.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import '../app_state_proxy_notifier.dart';

class PurchaseInvoiceState extends AppStateProxyNotifier {
  PurchaseInvoiceState({required super.appState}) {
    startWatchingAppState();
  }

  static const int _documentPageSize = 50;
  static const int _pageSize = 500;

  List<PurchaseInvoice> _purchaseInvoices = const [];
  bool _isPurchaseInvoicesLoading = false;
  bool _isMorePurchaseInvoicesLoading = false;
  bool _hasMorePurchaseInvoices = true;
  String? _purchaseInvoicesError;
  String _purchaseInvoiceSearch = '';
  String? _purchaseInvoiceStatus;
  int _purchaseInvoiceQueryVersion = 0;
  Future<void>? _purchaseInvoicesFetchInFlight;
  String? _buyingSupplierTypeIdsCacheKey;
  List<String>? _buyingSupplierTypeIdsCache;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.buyingPeriodYear,
    appState.buyingPeriodMonth,
    appState.buyingCompanyFilter,
    appState.buyingSupplierTypeFilter,
    appState.purchaseInvoiceTrendPoints,
    appState.warehouses,
  ];

  int get buyingPeriodYear => appState.buyingPeriodYear;
  int get buyingPeriodMonth => appState.buyingPeriodMonth;
  List<DocumentTrendPoint> get purchaseInvoiceTrendPoints =>
      appState.purchaseInvoiceTrendPoints;

  List<PurchaseInvoice> get purchaseInvoices => _purchaseInvoices;
  List<WarehouseInfo> get warehouses => appState.warehouses;
  FrappeService get frappeService => appState.frappeService;
  bool get isPurchaseInvoicesLoading => _isPurchaseInvoicesLoading;
  bool get isMorePurchaseInvoicesLoading => _isMorePurchaseInvoicesLoading;
  bool get hasMorePurchaseInvoices => _hasMorePurchaseInvoices;
  String? get purchaseInvoicesError => _purchaseInvoicesError;

  Future<void> refreshPurchaseInvoices() {
    final inFlight = _purchaseInvoicesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchPurchaseInvoices();
    _purchaseInvoicesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_purchaseInvoicesFetchInFlight, request)) {
        _purchaseInvoicesFetchInFlight = null;
      }
    });
  }

  Future<void> refreshWarehouses() => appState.refreshWarehouses();

  Future<void> loadMorePurchaseInvoices() async {
    if (_isPurchaseInvoicesLoading ||
        _isMorePurchaseInvoicesLoading ||
        !_hasMorePurchaseInvoices) {
      return;
    }

    _isMorePurchaseInvoicesLoading = true;
    final version = _purchaseInvoiceQueryVersion;
    notifyListeners();

    try {
      final page = await _fetchPurchaseInvoicePage(
        limitStart: _purchaseInvoices.length,
      );
      if (version != _purchaseInvoiceQueryVersion) return;
      final ids = _purchaseInvoices.map((invoice) => invoice.id).toSet();
      _purchaseInvoices = [
        ..._purchaseInvoices,
        ...page.where((invoice) => ids.add(invoice.id)),
      ];
      _hasMorePurchaseInvoices = page.length >= _documentPageSize;
      _purchaseInvoicesError = null;
    } catch (error) {
      if (version != _purchaseInvoiceQueryVersion) return;
      _purchaseInvoicesError = error.toString();
    } finally {
      if (version == _purchaseInvoiceQueryVersion) {
        _isMorePurchaseInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setPurchaseInvoiceQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _purchaseInvoiceSearch;
    final nextStatus = status;
    if (_purchaseInvoiceSearch == nextSearch &&
        _purchaseInvoiceStatus == nextStatus) {
      return;
    }
    _purchaseInvoiceSearch = nextSearch;
    _purchaseInvoiceStatus = nextStatus;
    _purchaseInvoicesFetchInFlight = null;
    await refreshPurchaseInvoices();
  }

  Future<PurchaseInvoice> loadPurchaseInvoiceDetail(String id) async {
    await appState.frappeService.ensureLoggedIn();
    final doc = await appState.frappeService.fetchDocument(
      'Purchase Invoice',
      id,
    );
    final invoice = PurchaseInvoice.fromJson(doc);
    _replacePurchaseInvoiceSnapshot(invoice);
    return invoice;
  }

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    if (doctype == 'Purchase Invoice') {
      await refreshPurchaseInvoices();
    }
  }

  Future<List<String>> fetchNamingSeries(String doctype) {
    return appState.fetchNamingSeries(doctype);
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    return appState.preferredWarehouse(options);
  }

  Future<PurchaseInvoice> createPurchaseInvoice({
    required String supplier,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required String namingSeries,
    required DateTime postingDate,
    required DateTime dueDate,
    required bool updateStock,
    String? warehouse,
    double? rate,
    String? company,
  }) async {
    final invoice = await appState.createPurchaseInvoice(
      supplier: supplier,
      itemCode: itemCode,
      qty: qty,
      items: items,
      namingSeries: namingSeries,
      postingDate: postingDate,
      dueDate: dueDate,
      updateStock: updateStock,
      warehouse: warehouse,
      rate: rate,
      company: company,
    );
    _purchaseInvoices = [
      invoice,
      ..._purchaseInvoices.where((row) => row.id != invoice.id),
    ];
    notifyListeners();
    await refreshPurchaseInvoices();
    return invoice;
  }

  Future<List<String>> fetchDocumentWorkflowActions({
    required String doctype,
    required String name,
  }) {
    return appState.fetchDocumentWorkflowActions(doctype: doctype, name: name);
  }

  Future<void> applyDocumentWorkflow({
    required String doctype,
    required String name,
    required String action,
    String? reason,
  }) {
    return appState.applyDocumentWorkflow(
      doctype: doctype,
      name: name,
      action: action,
      reason: reason ?? '',
    );
  }

  Future<void> _fetchPurchaseInvoices() async {
    if (appState.isSampleMode) {
      _purchaseInvoices = appState.purchaseInvoices;
      _purchaseInvoicesError = null;
      notifyListeners();
      return;
    }

    _isPurchaseInvoicesLoading = true;
    _purchaseInvoicesError = null;
    _hasMorePurchaseInvoices = true;
    _isMorePurchaseInvoicesLoading = false;
    final version = ++_purchaseInvoiceQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final docs = await _fetchPurchaseInvoicePage(limitStart: 0);
      if (version != _purchaseInvoiceQueryVersion) return;
      _purchaseInvoices = docs;
      _hasMorePurchaseInvoices = docs.length >= _documentPageSize;
      _purchaseInvoicesError = null;
    } catch (error) {
      if (version != _purchaseInvoiceQueryVersion) return;
      _purchaseInvoicesError = error.toString();
    } finally {
      if (version == _purchaseInvoiceQueryVersion) {
        _isPurchaseInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<PurchaseInvoice>> _fetchPurchaseInvoicePage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('posting_date'),
      ...?_statusFilters(_purchaseInvoiceStatus),
    ];
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds();
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Purchase Invoice',
      fields: const [
        'name',
        'supplier',
        'supplier_name',
        'status',
        'docstatus',
        'posting_date',
        'grand_total',
        'outstanding_amount',
        'due_date',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_purchaseInvoiceSearch, const [
        'name',
        'supplier',
        'supplier_name',
      ]),
    );
    return data
        .where((item) => _matchesBuyingSupplierType(item, supplierTypeIds))
        .map(PurchaseInvoice.fromJson)
        .toList();
  }

  void _replacePurchaseInvoiceSnapshot(PurchaseInvoice invoice) {
    final index = _purchaseInvoices.indexWhere((item) => item.id == invoice.id);
    if (index < 0) return;
    _purchaseInvoices = List<PurchaseInvoice>.from(_purchaseInvoices)
      ..[index] = invoice;
    notifyListeners();
  }

  List<List<dynamic>> _buyingPeriodFilters(String dateField) {
    final filters = <List<dynamic>>[
      [
        dateField,
        '>=',
        DateRangePresets.toFrappeDate(appState.buyingPeriodFrom),
      ],
      [dateField, '<=', DateRangePresets.toFrappeDate(appState.buyingPeriodTo)],
    ];
    final company = appState.buyingCompanyFilter.trim();
    if (company.isNotEmpty) {
      filters.add(['company', '=', company]);
    }
    return filters;
  }

  List<List<dynamic>>? _statusFilters(String? status) {
    if (status == null || status.trim().isEmpty) return null;
    return [
      ['status', '=', status.trim()],
    ];
  }

  List<List<dynamic>>? _searchFilters(String search, List<String> fields) {
    final query = search.trim();
    if (query.isEmpty) return null;
    return fields
        .map<List<dynamic>>((field) => [field, 'like', '%$query%'])
        .toList();
  }

  bool _matchesBuyingSupplierType(
    Map<String, dynamic> row,
    List<String>? supplierIds,
  ) {
    if (supplierIds == null) return true;
    if (supplierIds.isEmpty) return false;
    return supplierIds.contains(row['supplier']?.toString() ?? '');
  }

  Future<List<String>?> _buyingSupplierTypeSupplierIds() async {
    final type = appState.buyingSupplierTypeFilter.trim().toLowerCase();
    if (type.isEmpty || type == 'all') return null;
    if (_buyingSupplierTypeIdsCacheKey == type &&
        _buyingSupplierTypeIdsCache != null) {
      return _buyingSupplierTypeIdsCache;
    }

    final internal = type == 'internal';
    List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchAllResourcePages(
        doctype: 'Supplier',
        fields: const ['name', 'is_internal_supplier'],
        maxRows: null,
      );
    } catch (_) {
      return null;
    }

    final ids = rows
        .where(
          (row) =>
              NumParse.asInt(row['is_internal_supplier']) == (internal ? 1 : 0),
        )
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    _buyingSupplierTypeIdsCacheKey = type;
    _buyingSupplierTypeIdsCache = ids;
    return ids;
  }

  Future<List<Map<String, dynamic>>> _fetchAllResourcePages({
    required String doctype,
    required List<String> fields,
    List<List<dynamic>>? filters,
    int? maxRows,
  }) {
    return walkFrappePages(
      pageSize: _pageSize,
      maxRows: maxRows,
      fetchPage: (start, limit) => _fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        filters: filters,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchResourceWithFieldFallback({
    required String doctype,
    required List<String> fields,
    required int limit,
    int limitStart = 0,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    var remainingFields = List<String>.from(fields);
    var currentOrderBy = orderBy;
    while (remainingFields.isNotEmpty) {
      try {
        return await appState.frappeService.fetchResource(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          orderBy: currentOrderBy,
          filters: filters,
          orFilters: orFilters,
        );
      } catch (error) {
        final text = error.toString();
        final badField = RegExp(
          r'Field not permitted in query:\s*([a-zA-Z0-9_]+)',
        ).firstMatch(text)?.group(1);
        if (badField != null && remainingFields.contains(badField)) {
          remainingFields.remove(badField);
          continue;
        }
        if (currentOrderBy != null &&
            (text.contains('Unknown column') ||
                text.contains('Field not permitted in query'))) {
          currentOrderBy = null;
          continue;
        }
        rethrow;
      }
    }
    return const [];
  }
}
