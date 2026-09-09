import '../../models/inventory_item.dart';
import '../../models/material_request.dart';
import '../../models/warehouse_info.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../app_state_proxy_notifier.dart';
import 'purchasing_filter_state.dart';

class MaterialRequestState extends AppStateProxyNotifier {
  MaterialRequestState({required super.appState, required this.filterState}) {
    startWatchingAppState();
  }

  static const int _documentPageSize = 50;
  static const int _pageSize = 500;

  List<MaterialRequest> _materialRequests = const [];
  bool _isMaterialRequestsLoading = false;
  bool _isMoreMaterialRequestsLoading = false;
  bool _hasMoreMaterialRequests = true;
  String? _materialRequestsError;
  String _materialRequestSearch = '';
  String? _materialRequestStatus;
  int _materialRequestQueryVersion = 0;
  Future<void>? _materialRequestsFetchInFlight;
  PurchasingFilterState filterState;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.inventory,
    appState.warehouses,
    appState.buyingCompanies,
  ];

  int get buyingPeriodYear => filterState.buyingPeriodYear;
  int get buyingPeriodMonth => filterState.buyingPeriodMonth;
  List<InventoryItem> get inventory => appState.inventory;
  List<WarehouseInfo> get warehouses => appState.warehouses;
  List<String> get buyingCompanies => appState.buyingCompanies;
  FrappeService get frappeService => appState.frappeService;

  List<MaterialRequest> get materialRequests => _materialRequests;
  bool get isMaterialRequestsLoading => _isMaterialRequestsLoading;
  bool get isMoreMaterialRequestsLoading => _isMoreMaterialRequestsLoading;
  bool get hasMoreMaterialRequests => _hasMoreMaterialRequests;
  String? get materialRequestsError => _materialRequestsError;

  void updateFilterState(PurchasingFilterState value) {
    filterState = value;
  }

  Future<void> refreshInventory() => appState.refreshInventory();
  Future<void> refreshWarehouses() => appState.refreshWarehouses();
  Future<void> loadBuyingFilterOptions() => appState.loadBuyingFilterOptions();
  Future<void> refreshMaterialRequests() {
    final inFlight = _materialRequestsFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchMaterialRequests();
    _materialRequestsFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_materialRequestsFetchInFlight, request)) {
        _materialRequestsFetchInFlight = null;
      }
    });
  }

  Future<void> refreshPurchaseOrders() => appState.refreshPurchaseOrders();

  Future<void> loadMoreMaterialRequests() async {
    if (_isMaterialRequestsLoading ||
        _isMoreMaterialRequestsLoading ||
        !_hasMoreMaterialRequests) {
      return;
    }

    _isMoreMaterialRequestsLoading = true;
    final version = _materialRequestQueryVersion;
    notifyListeners();

    try {
      final page = await _fetchMaterialRequestPage(
        limitStart: _materialRequests.length,
      );
      if (version != _materialRequestQueryVersion) return;
      final ids = _materialRequests.map((request) => request.id).toSet();
      _materialRequests = [
        ..._materialRequests,
        ...page.where((request) => ids.add(request.id)),
      ];
      _hasMoreMaterialRequests = page.length >= _documentPageSize;
      _materialRequestsError = null;
    } catch (error) {
      if (version != _materialRequestQueryVersion) return;
      _hasMoreMaterialRequests = false;
      if (_materialRequests.isEmpty) {
        _materialRequestsError = error.toString();
      }
    } finally {
      if (version == _materialRequestQueryVersion) {
        _isMoreMaterialRequestsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setMaterialRequestQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _materialRequestSearch;
    final nextStatus = status;
    if (_materialRequestSearch == nextSearch &&
        _materialRequestStatus == nextStatus) {
      return;
    }
    _materialRequestSearch = nextSearch;
    _materialRequestStatus = nextStatus;
    _materialRequestsFetchInFlight = null;
    await refreshMaterialRequests();
  }

  Future<MaterialRequest> loadMaterialRequestDetail(String id) async {
    await appState.frappeService.ensureLoggedIn();
    final doc = await appState.frappeService.fetchDocument(
      'Material Request',
      id,
    );
    final request = MaterialRequest.fromJson(doc);
    _replaceMaterialRequestSnapshot(request);
    return request;
  }

  Future<MaterialRequest> createMaterialRequest({
    required String materialRequestType,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required DateTime transactionDate,
    required DateTime scheduleDate,
    String? company,
    String? warehouse,
  }) async {
    final request = await appState.createMaterialRequest(
      materialRequestType: materialRequestType,
      itemCode: itemCode,
      qty: qty,
      items: items,
      transactionDate: transactionDate,
      scheduleDate: scheduleDate,
      company: company,
      warehouse: warehouse,
    );
    _materialRequests = [
      request,
      ..._materialRequests.where((row) => row.id != request.id),
    ];
    notifyListeners();
    await refreshMaterialRequests();
    return request;
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

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    if (doctype == 'Material Request') {
      await refreshMaterialRequests();
    }
  }

  Future<List<String>> fetchNamingSeries(String doctype) {
    return appState.fetchNamingSeries(doctype);
  }

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    return appState.preferredWarehouse(options);
  }

  Future<void> _fetchMaterialRequests() async {
    if (appState.isSampleMode) {
      _materialRequests = appState.materialRequests;
      _materialRequestsError = null;
      notifyListeners();
      return;
    }

    _isMaterialRequestsLoading = true;
    _materialRequestsError = null;
    _hasMoreMaterialRequests = true;
    _isMoreMaterialRequestsLoading = false;
    final version = ++_materialRequestQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final docs = await _fetchMaterialRequestPage(limitStart: 0);
      if (version != _materialRequestQueryVersion) return;
      _materialRequests = docs;
      _hasMoreMaterialRequests = docs.length >= _documentPageSize;
      _materialRequestsError = null;
    } catch (error) {
      if (version != _materialRequestQueryVersion) return;
      _hasMoreMaterialRequests = false;
      _materialRequestsError = error.toString();
    } finally {
      if (version == _materialRequestQueryVersion) {
        _isMaterialRequestsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<MaterialRequest>> _fetchMaterialRequestPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('transaction_date'),
      ...?_statusFilters(_materialRequestStatus),
    ];
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Material Request',
      fields: const [
        'name',
        'material_request_type',
        'status',
        'docstatus',
        'transaction_date',
        'schedule_date',
        'company',
        'total_qty',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'transaction_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_materialRequestSearch, const [
        'name',
        'material_request_type',
        'company',
      ]),
    );

    return _attachMaterialRequestItems(
      data.map(MaterialRequest.fromJson).toList(),
    );
  }

  Future<List<MaterialRequest>> _attachMaterialRequestItems(
    List<MaterialRequest> requests,
  ) async {
    if (requests.isEmpty) return requests;
    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Material Request Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'qty',
          'ordered_qty',
          'stock_uom',
          'warehouse',
          'schedule_date',
        ],
        filters: [
          ['parent', 'in', requests.map((request) => request.id).toList()],
        ],
        maxRows: 2000,
      );
      final grouped = <String, List<MaterialRequestItem>>{};
      for (final row in rows) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isEmpty) continue;
        grouped
            .putIfAbsent(parent, () => [])
            .add(MaterialRequestItem.fromJson(row));
      }
      return [
        for (final request in requests)
          request.copyWith(items: grouped[request.id] ?? request.items),
      ];
    } catch (_) {
      return requests;
    }
  }

  void _replaceMaterialRequestSnapshot(MaterialRequest request) {
    final index = _materialRequests.indexWhere((item) => item.id == request.id);
    if (index < 0) return;
    _materialRequests = List<MaterialRequest>.from(_materialRequests)
      ..[index] = request;
    notifyListeners();
  }

  List<List<dynamic>> _buyingPeriodFilters(String dateField) {
    final filters = <List<dynamic>>[
      [
        dateField,
        '>=',
        DateRangePresets.toFrappeDate(filterState.buyingPeriodFrom),
      ],
      [
        dateField,
        '<=',
        DateRangePresets.toFrappeDate(filterState.buyingPeriodTo),
      ],
    ];
    final company = filterState.buyingCompanyFilter.trim();
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
