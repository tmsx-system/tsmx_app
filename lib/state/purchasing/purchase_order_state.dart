import '../../models/erp_summary.dart';
import '../../models/purchase_invoice.dart';
import '../../models/purchase_order.dart';
import '../../models/purchase_receipt.dart';
import '../../models/supplier_price_comparison.dart';
import '../../models/warehouse_info.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import '../app_state_proxy_notifier.dart';

class PurchaseOrderState extends AppStateProxyNotifier {
  PurchaseOrderState({required super.appState}) {
    startWatchingAppState();
  }

  static const int _documentPageSize = 50;
  static const int _pageSize = 500;

  List<PurchaseOrder> _purchaseOrders = const [];
  bool _isPurchaseOrdersLoading = false;
  bool _isMorePurchaseOrdersLoading = false;
  bool _hasMorePurchaseOrders = true;
  String? _purchaseOrdersError;
  String _purchaseOrderSearch = '';
  String? _purchaseOrderStatus;
  int _purchaseOrderQueryVersion = 0;
  Future<void>? _purchaseOrdersFetchInFlight;
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
    appState.isOrderSummaryLoading,
    appState.purchaseOrderTrendPoints,
    appState.warehouses,
    appState.buyingCompanies,
  ];

  int get buyingPeriodYear => appState.buyingPeriodYear;
  int get buyingPeriodMonth => appState.buyingPeriodMonth;
  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;
  List<DocumentTrendPoint> get purchaseOrderTrendPoints =>
      appState.purchaseOrderTrendPoints;

  List<PurchaseOrder> get purchaseOrders => _purchaseOrders;
  List<WarehouseInfo> get warehouses => appState.warehouses;
  List<String> get buyingCompanies => appState.buyingCompanies;
  FrappeService get frappeService => appState.frappeService;
  bool get isPurchaseOrdersLoading => _isPurchaseOrdersLoading;
  bool get isMorePurchaseOrdersLoading => _isMorePurchaseOrdersLoading;
  bool get hasMorePurchaseOrders => _hasMorePurchaseOrders;
  String? get purchaseOrdersError => _purchaseOrdersError;

  Future<void> refreshPurchaseOrders() {
    final inFlight = _purchaseOrdersFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchPurchaseOrders();
    _purchaseOrdersFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_purchaseOrdersFetchInFlight, request)) {
        _purchaseOrdersFetchInFlight = null;
      }
    });
  }

  Future<void> refreshWarehouses() => appState.refreshWarehouses();

  Future<void> loadMorePurchaseOrders() async {
    if (_isPurchaseOrdersLoading ||
        _isMorePurchaseOrdersLoading ||
        !_hasMorePurchaseOrders) {
      return;
    }

    _isMorePurchaseOrdersLoading = true;
    final version = _purchaseOrderQueryVersion;
    notifyListeners();

    try {
      final nextPage = await _fetchPurchaseOrderPage(
        limitStart: _purchaseOrders.length,
      );
      if (version != _purchaseOrderQueryVersion) return;
      final existingIds = _purchaseOrders.map((order) => order.id).toSet();
      _purchaseOrders = [
        ..._purchaseOrders,
        ...nextPage.where((order) => existingIds.add(order.id)),
      ];
      _hasMorePurchaseOrders = nextPage.length >= _documentPageSize;
      _purchaseOrdersError = null;
    } catch (error) {
      if (version != _purchaseOrderQueryVersion) return;
      _purchaseOrdersError = error.toString();
    } finally {
      if (version == _purchaseOrderQueryVersion) {
        _isMorePurchaseOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setPurchaseOrderQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _purchaseOrderSearch;
    final nextStatus = status;
    if (_purchaseOrderSearch == nextSearch &&
        _purchaseOrderStatus == nextStatus) {
      return;
    }
    _purchaseOrderSearch = nextSearch;
    _purchaseOrderStatus = nextStatus;
    _purchaseOrdersFetchInFlight = null;
    await refreshPurchaseOrders();
  }

  Future<PurchaseOrder> loadPurchaseOrderDetail(String orderId) async {
    await appState.frappeService.ensureLoggedIn();
    final doc = await appState.frappeService.fetchDocument(
      'Purchase Order',
      orderId,
    );
    final order = PurchaseOrder.fromJson(doc);
    _replacePurchaseOrderSnapshot(order);
    return order;
  }

  Future<void> deletePurchaseOrder(String orderId) async {
    await appState.deletePurchaseOrder(orderId);
    _purchaseOrders = _purchaseOrders
        .where((order) => order.id != orderId)
        .toList();
    notifyListeners();
  }

  Future<List<String>> fetchNamingSeries(String doctype) {
    return appState.fetchNamingSeries(doctype);
  }

  Future<List<Map<String, dynamic>>> fetchPurchasableItems({
    String query = '',
    int limit = 20,
  }) {
    return appState.fetchPurchasableItems(query: query, limit: limit);
  }

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    return appState.preferredWarehouse(options);
  }

  Future<PurchaseOrder> createPurchaseOrder({
    required String supplier,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required String namingSeries,
    required DateTime requiredBy,
    String? warehouse,
    String? company,
    double? rate,
    DateTime? transactionDate,
    String? noted,
  }) async {
    final order = await appState.createPurchaseOrder(
      supplier: supplier,
      itemCode: itemCode,
      qty: qty,
      items: items,
      namingSeries: namingSeries,
      requiredBy: requiredBy,
      warehouse: warehouse,
      company: company,
      rate: rate,
      transactionDate: transactionDate,
      noted: noted,
    );
    _purchaseOrders = [
      order,
      ..._purchaseOrders.where((row) => row.id != order.id),
    ];
    notifyListeners();
    await refreshPurchaseOrders();
    return order;
  }

  Future<PurchaseOrder> updatePurchaseOrder({
    required String orderId,
    String? supplier,
    String? itemCode,
    double? qty,
    String? warehouse,
    String? company,
    double? rate,
    List<Map<String, dynamic>>? items,
    DateTime? transactionDate,
    DateTime? requiredBy,
    String? noted,
  }) async {
    final order = await appState.updatePurchaseOrder(
      orderId: orderId,
      supplier: supplier,
      itemCode: itemCode,
      qty: qty,
      warehouse: warehouse,
      company: company,
      rate: rate,
      items: items,
      transactionDate: transactionDate,
      requiredBy: requiredBy,
      noted: noted,
    );
    _replacePurchaseOrderSnapshot(order);
    return order;
  }

  Future<void> refreshPurchaseReceipts() => appState.refreshPurchaseReceipts();
  Future<void> refreshPurchaseInvoices() => appState.refreshPurchaseInvoices();

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    if (doctype == 'Purchase Order') {
      await refreshPurchaseOrders();
    }
  }

  Future<void> cancelDocument(String doctype, String name) {
    return appState.cancelDocument(doctype, name);
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

  Future<PurchaseReceipt> createPurchaseReceiptFromPurchaseOrder(
    String orderId,
  ) {
    return appState.createPurchaseReceiptFromPurchaseOrder(orderId);
  }

  Future<PurchaseInvoice> createPurchaseInvoiceFromPurchaseOrder(
    String orderId,
  ) {
    return appState.createPurchaseInvoiceFromPurchaseOrder(orderId);
  }

  Future<SupplierPriceComparison> fetchSupplierPriceComparison({
    required String itemCode,
    String itemName = '',
  }) {
    return appState.fetchSupplierPriceComparison(
      itemCode: itemCode,
      itemName: itemName,
    );
  }

  Future<void> _fetchPurchaseOrders() async {
    if (appState.isSampleMode) {
      _purchaseOrders = appState.purchaseOrders;
      _purchaseOrdersError = null;
      notifyListeners();
      return;
    }

    _isPurchaseOrdersLoading = true;
    _purchaseOrdersError = null;
    _hasMorePurchaseOrders = true;
    _isMorePurchaseOrdersLoading = false;
    final version = ++_purchaseOrderQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final orders = await _fetchPurchaseOrderPage(limitStart: 0);
      if (version != _purchaseOrderQueryVersion) return;
      _purchaseOrders = orders;
      _hasMorePurchaseOrders = orders.length >= _documentPageSize;
      _purchaseOrdersError = null;
    } catch (error) {
      if (version != _purchaseOrderQueryVersion) return;
      _hasMorePurchaseOrders = false;
      _purchaseOrdersError = error.toString();
    } finally {
      if (version == _purchaseOrderQueryVersion) {
        _isPurchaseOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<PurchaseOrder>> _fetchPurchaseOrderPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('transaction_date'),
      ...?_purchaseOrderFilters(_purchaseOrderStatus),
    ];
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds();
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Purchase Order',
      fields: const [
        'name',
        'supplier',
        'supplier_name',
        'status',
        'docstatus',
        'transaction_date',
        'schedule_date',
        'total_qty',
        'base_net_total',
        'net_total',
        'grand_total',
        'creation',
        'modified',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'modified desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_purchaseOrderSearch, const [
        'name',
        'supplier',
        'supplier_name',
      ]),
    );

    final orders = data
        .where((item) => _matchesBuyingSupplierType(item, supplierTypeIds))
        .map(PurchaseOrder.fromJson)
        .toList();
    return _attachPurchaseOrderItems(orders);
  }

  Future<List<PurchaseOrder>> _attachPurchaseOrderItems(
    List<PurchaseOrder> orders,
  ) async {
    if (orders.isEmpty) return orders;
    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Purchase Order Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'qty',
          'rate',
          'warehouse',
        ],
        filters: [
          ['parent', 'in', orders.map((order) => order.id).toList()],
        ],
        maxRows: 2000,
      );
      final grouped = <String, List<PurchaseOrderItem>>{};
      for (final row in rows) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isEmpty) continue;
        grouped
            .putIfAbsent(parent, () => [])
            .add(PurchaseOrderItem.fromJson(row));
      }
      return [
        for (final order in orders)
          order.copyWith(items: grouped[order.id] ?? order.items),
      ];
    } catch (_) {
      return orders;
    }
  }

  void _replacePurchaseOrderSnapshot(PurchaseOrder order) {
    final index = _purchaseOrders.indexWhere((item) => item.id == order.id);
    if (index < 0) return;
    _purchaseOrders = List<PurchaseOrder>.from(_purchaseOrders)
      ..[index] = order;
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

  List<List<dynamic>>? _purchaseOrderFilters(String? status) {
    if (status == 'To Receive and To Bill') {
      return [
        [
          'status',
          'in',
          ['To Receive and Bill', 'To Receive and To Bill'],
        ],
      ];
    }
    return _statusFilters(status);
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
