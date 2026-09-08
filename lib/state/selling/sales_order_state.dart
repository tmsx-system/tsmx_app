import '../../models/delivery_note.dart';
import '../../models/erp_summary.dart';
import '../../models/sales_invoice.dart';
import '../../models/sales_order.dart';
import '../../models/sales_order_insight.dart';
import '../../models/sales_workspace.dart';
import '../../models/stock_ledger_movement.dart';
import '../../models/warehouse_info.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class SalesOrderState extends AppStateProxyNotifier {
  SalesOrderState({required super.appState}) {
    startWatchingAppState();
  }

  static const int _documentPageSize = 50;
  static const int _pageSize = 500;

  List<SalesOrder> _salesOrders = const [];
  bool _isSalesOrdersLoading = false;
  bool _isMoreSalesOrdersLoading = false;
  bool _hasMoreSalesOrders = true;
  String? _salesOrdersError;
  String _salesOrderSearch = '';
  String? _salesOrderStatus;
  int _salesOrderQueryVersion = 0;
  Future<void>? _salesOrdersFetchInFlight;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.mobileBoot,
    appState.currentSalesPerson,
    appState.sellingPeriodYear,
    appState.sellingPeriodMonth,
    appState.sellingCompanyFilter,
    appState.sellingCustomerTypeFilter,
    appState.isOrderSummaryLoading,
    appState.salesOrderTrendPoints,
  ];

  int get sellingPeriodYear => appState.sellingPeriodYear;
  int get sellingPeriodMonth => appState.sellingPeriodMonth;
  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;
  List<DocumentTrendPoint> get salesOrderTrendPoints =>
      appState.salesOrderTrendPoints;
  FrappeService get frappeService => appState.frappeService;
  MobileAccess get mobileAccess => appState.mobileAccess;
  String? get currentSalesPerson => appState.currentSalesPerson;
  String? get salesIdentityError => appState.salesIdentityError;
  List<WarehouseInfo> get warehouses => appState.warehouses;
  List<String> get sellingCompanies => appState.sellingCompanies;

  List<SalesOrder> get salesOrders => _salesOrders;
  bool get isSalesOrdersLoading => _isSalesOrdersLoading;
  bool get isMoreSalesOrdersLoading => _isMoreSalesOrdersLoading;
  bool get hasMoreSalesOrders => _hasMoreSalesOrders;
  String? get salesOrdersError => _salesOrdersError;

  Future<void> refreshSalesOrders() {
    final inFlight = _salesOrdersFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchSalesOrders();
    _salesOrdersFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_salesOrdersFetchInFlight, request)) {
        _salesOrdersFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchSalesOrders() async {
    if (appState.isSampleMode) {
      _salesOrders = appState.salesOrders;
      notifyListeners();
      return;
    }

    _isSalesOrdersLoading = true;
    _salesOrdersError = null;
    _hasMoreSalesOrders = true;
    _isMoreSalesOrdersLoading = false;
    final version = ++_salesOrderQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final docs = await _fetchSalesOrderPage(limitStart: 0);
      if (version != _salesOrderQueryVersion) return;
      _salesOrders = docs;
      _hasMoreSalesOrders = docs.length >= _documentPageSize;
      _salesOrdersError = null;
    } catch (error) {
      if (version != _salesOrderQueryVersion) return;
      _salesOrdersError = error.toString();
    } finally {
      if (version == _salesOrderQueryVersion) {
        _isSalesOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreSalesOrders() async {
    if (_isSalesOrdersLoading ||
        _isMoreSalesOrdersLoading ||
        !_hasMoreSalesOrders) {
      return;
    }

    _isMoreSalesOrdersLoading = true;
    final version = _salesOrderQueryVersion;
    notifyListeners();

    try {
      final page = await _fetchSalesOrderPage(limitStart: _salesOrders.length);
      if (version != _salesOrderQueryVersion) return;
      final ids = _salesOrders.map((order) => order.id).toSet();
      _salesOrders = [
        ..._salesOrders,
        ...page.where((order) => ids.add(order.id)),
      ];
      _hasMoreSalesOrders = page.length >= _documentPageSize;
      _salesOrdersError = null;
    } catch (error) {
      if (version != _salesOrderQueryVersion) return;
      _salesOrdersError = error.toString();
    } finally {
      if (version == _salesOrderQueryVersion) {
        _isMoreSalesOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setSalesOrderQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _salesOrderSearch;
    final nextStatus = status;
    if (_salesOrderSearch == nextSearch && _salesOrderStatus == nextStatus) {
      return;
    }
    _salesOrderSearch = nextSearch;
    _salesOrderStatus = nextStatus;
    _salesOrdersFetchInFlight = null;
    await refreshSalesOrders();
  }

  Future<SalesOrder> loadSalesOrderDetail(String orderId) async {
    final order = await appState.loadSalesOrderDetail(orderId);
    _replaceSalesOrderSnapshot(order);
    return order;
  }

  Future<List<SalesOrder>> _fetchSalesOrderPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._sellingPeriodFilters('transaction_date'),
      ...?_statusFilters(_salesOrderStatus),
      ...?await _salesDocumentScopeFilters(),
    ];
    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Sales Order',
      fields: const [
        'name',
        'owner',
        'customer',
        'customer_name',
        'grand_total',
        'status',
        'workflow_state',
        'docstatus',
        'transaction_date',
        'delivery_date',
        'total_qty',
        'per_delivered',
        'per_billed',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'transaction_date desc, name desc',
      filters: filters.isEmpty ? null : filters,
      orFilters: _searchFilters(_salesOrderSearch, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );
    return _attachSalesOrderItems(
      rows.map((row) => SalesOrder.fromJson(row)).toList(),
    );
  }

  Future<List<SalesOrder>> _attachSalesOrderItems(
    List<SalesOrder> orders,
  ) async {
    if (orders.isEmpty) return orders;
    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Sales Order Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'qty',
          'rate',
          'discount_amount',
          'warehouse',
        ],
        filters: [
          ['parent', 'in', orders.map((order) => order.id).toList()],
        ],
        maxRows: 2000,
      );
      final grouped = <String, List<SalesOrderItem>>{};
      for (final row in rows) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isEmpty) continue;
        grouped.putIfAbsent(parent, () => []).add(SalesOrderItem.fromJson(row));
      }
      return [
        for (final order in orders)
          order.copyWith(items: grouped[order.id] ?? order.items),
      ];
    } catch (_) {
      return orders;
    }
  }

  void _replaceSalesOrderSnapshot(SalesOrder order) {
    final index = _salesOrders.indexWhere((item) => item.id == order.id);
    if (index < 0) return;
    _salesOrders = List<SalesOrder>.from(_salesOrders)..[index] = order;
    notifyListeners();
  }

  Future<List<List<dynamic>>?> _salesDocumentScopeFilters() async {
    if (!appState.mobileAccess.shouldScopeSalesData) return const [];
    final salesPerson = await appState.resolveCurrentSalesIdentity();
    final normalized = salesPerson?.trim() ?? '';
    if (normalized.isEmpty) {
      throw Exception(
        appState.salesIdentityError ??
            'Sales Person user login belum tersedia.',
      );
    }
    return [
      ['Sales Team', 'sales_person', '=', normalized],
    ];
  }

  List<List<dynamic>> _sellingPeriodFilters(String dateField) {
    final filters = <List<dynamic>>[
      [
        dateField,
        '>=',
        DateRangePresets.toFrappeDate(appState.sellingPeriodFrom),
      ],
      [
        dateField,
        '<=',
        DateRangePresets.toFrappeDate(appState.sellingPeriodTo),
      ],
    ];
    final company = appState.sellingCompanyFilter.trim();
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
        if (_usesSalesTeamChildFilter(filters)) {
          return appState.frappeService.fetchReportView(
            doctype,
            fields: remainingFields,
            limit: limit,
            limitStart: limitStart,
            orderBy: currentOrderBy,
            filters: filters,
            orFilters: orFilters,
          );
        }
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

  bool _usesSalesTeamChildFilter(List<List<dynamic>>? filters) {
    if (filters == null) return false;
    return filters.any((filter) {
      if (filter.length < 4) return false;
      if (filter.first.toString().trim() != 'Sales Team') return false;
      final field = filter[1].toString().trim();
      return field == 'parent_sales_person' || field == 'sales_person';
    });
  }

  Future<List<int>> downloadSalesOrderPdf(String name) {
    return appState.downloadSalesOrderPdf(name);
  }

  Future<List<DeliveryNote>> fetchDeliveryNotesForSalesOrder(String id) {
    return appState.fetchDeliveryNotesForSalesOrder(id);
  }

  Future<List<SalesInvoice>> fetchSalesInvoicesForSalesOrder(String id) {
    return appState.fetchSalesInvoicesForSalesOrder(id);
  }

  Future<bool> canSubmitDoctype(String doctype) {
    return appState.canSubmitDoctype(doctype);
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
  }) async {
    await appState.applyDocumentWorkflow(
      doctype: doctype,
      name: name,
      action: action,
      reason: reason ?? '',
    );
    await refreshSalesOrders();
  }

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    await refreshSalesOrders();
  }

  Future<CustomerSalesInsight> fetchCustomerSalesInsight(
    String customer, {
    String? company,
  }) {
    return appState.fetchCustomerSalesInsight(customer, company: company);
  }

  Future<ItemSalesInsight> fetchItemSalesInsight(
    String itemCode, {
    String? customer,
    String? company,
    String? priceList,
    String? currency,
    String? warehouse,
    String? customerGroup,
    DateTime? transactionDate,
    double qty = 1,
    bool ignorePricingRule = false,
  }) {
    return appState.fetchItemSalesInsight(
      itemCode,
      customer: customer,
      company: company,
      priceList: priceList,
      currency: currency,
      warehouse: warehouse,
      customerGroup: customerGroup,
      transactionDate: transactionDate,
      qty: qty,
      ignorePricingRule: ignorePricingRule,
    );
  }

  Future<List<Map<String, dynamic>>> fetchSellableItems({
    String query = '',
    int limit = 20,
  }) {
    return appState.fetchSellableItems(query: query, limit: limit);
  }

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    return appState.preferredWarehouse(options);
  }

  Future<void> refreshWarehouses() {
    return appState.refreshWarehouses();
  }

  Future<List<String>> fetchNamingSeries(String doctype) {
    return appState.fetchNamingSeries(doctype);
  }

  Future<DeliveryNote> createDeliveryNoteFromSalesOrder(
    String soId, {
    required String namingSeries,
  }) {
    return appState.createDeliveryNoteFromSalesOrder(
      soId,
      namingSeries: namingSeries,
    );
  }

  Future<SalesInvoice> createSalesInvoiceFromSalesOrder(
    String soId, {
    required String namingSeries,
  }) {
    return appState.createSalesInvoiceFromSalesOrder(
      soId,
      namingSeries: namingSeries,
    );
  }

  Future<List<SalesCustomerOption>> fetchSalesCustomers() {
    return appState.fetchSalesCustomers();
  }

  Future<SalesOrder> createSalesOrder({
    required String customer,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    String? warehouse,
    double? rate,
    String? series,
    String? costCenter,
    String? company,
    String? currency,
    String? sellingPriceList,
    String? priceListCurrency,
    bool ignorePricingRule = false,
    String? salesPerson,
    List<Map<String, dynamic>>? salesTeam,
    String? noted,
    DateTime? transactionDate,
    DateTime? deliveryDate,
    bool refreshAfterSave = true,
  }) async {
    final order = await appState.createSalesOrder(
      customer: customer,
      itemCode: itemCode,
      qty: qty,
      items: items,
      warehouse: warehouse,
      rate: rate,
      series: series,
      costCenter: costCenter,
      company: company,
      currency: currency,
      sellingPriceList: sellingPriceList,
      priceListCurrency: priceListCurrency,
      ignorePricingRule: ignorePricingRule,
      salesPerson: salesPerson,
      salesTeam: salesTeam,
      noted: noted,
      transactionDate: transactionDate,
      deliveryDate: deliveryDate,
      refreshAfterSave: refreshAfterSave,
    );
    _salesOrders = [order, ..._salesOrders.where((row) => row.id != order.id)];
    notifyListeners();
    return order;
  }

  Future<SalesOrder> updateSalesOrder({
    required String orderId,
    String? customer,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    String? warehouse,
    double? rate,
    String? costCenter,
    String? company,
    String? currency,
    String? sellingPriceList,
    String? priceListCurrency,
    bool? ignorePricingRule,
    String? salesPerson,
    List<Map<String, dynamic>>? salesTeam,
    String? noted,
    DateTime? transactionDate,
    DateTime? deliveryDate,
    String? status,
    bool refreshAfterSave = true,
  }) async {
    final order = await appState.updateSalesOrder(
      orderId: orderId,
      customer: customer,
      itemCode: itemCode,
      qty: qty,
      items: items,
      warehouse: warehouse,
      rate: rate,
      costCenter: costCenter,
      company: company,
      currency: currency,
      sellingPriceList: sellingPriceList,
      priceListCurrency: priceListCurrency,
      ignorePricingRule: ignorePricingRule,
      salesPerson: salesPerson,
      salesTeam: salesTeam,
      noted: noted,
      transactionDate: transactionDate,
      deliveryDate: deliveryDate,
      status: status,
      refreshAfterSave: refreshAfterSave,
    );
    _replaceSalesOrderSnapshot(order);
    return order;
  }

  Future<Map<String, dynamic>> createCustomer({
    required String customerName,
    required String customerType,
    required String namingSeries,
    required String paymentTerms,
    required String company,
    String? customerGroup,
    String? territory,
  }) {
    return appState.createCustomer(
      customerName: customerName,
      customerType: customerType,
      namingSeries: namingSeries,
      paymentTerms: paymentTerms,
      company: company,
      customerGroup: customerGroup,
      territory: territory,
    );
  }

  Future<void> uploadSalesOrderAttachment(String orderId, String filePath) {
    return appState.uploadSalesOrderAttachment(orderId, filePath);
  }

  Future<List<CustomerPurchaseHistory>> fetchCustomerPurchaseHistory({
    required String customer,
    required String doctype,
    String? company,
    int offset = 0,
    int limit = 20,
  }) {
    return appState.fetchCustomerPurchaseHistory(
      customer: customer,
      doctype: doctype,
      company: company,
      offset: offset,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> loadSalesHistoryDetail(
    String doctype,
    String name,
  ) {
    return appState.loadSalesHistoryDetail(doctype, name);
  }

  Future<StockLedgerResult> fetchStockLedgerForItem({
    required String itemCode,
    required DateTime from,
    required DateTime to,
  }) {
    return appState.fetchStockLedgerForItem(
      itemCode: itemCode,
      from: from,
      to: to,
    );
  }
}
