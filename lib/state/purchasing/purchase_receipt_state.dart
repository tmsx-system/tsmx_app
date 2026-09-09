import '../../models/purchase_receipt.dart';
import '../../models/quality_inspection_record.dart';
import '../../models/warehouse_info.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import '../app_state_proxy_notifier.dart';
import 'purchasing_filter_state.dart';

class PurchaseReceiptState extends AppStateProxyNotifier {
  PurchaseReceiptState({required super.appState, required this.filterState}) {
    startWatchingAppState();
  }

  static const int _documentPageSize = 50;
  static const int _pageSize = 500;

  List<PurchaseReceipt> _purchaseReceipts = const [];
  bool _isPurchaseReceiptsLoading = false;
  bool _isMorePurchaseReceiptsLoading = false;
  bool _hasMorePurchaseReceipts = true;
  String? _purchaseReceiptsError;
  String _purchaseReceiptSearch = '';
  String? _purchaseReceiptStatus;
  int _purchaseReceiptQueryVersion = 0;
  Future<void>? _purchaseReceiptsFetchInFlight;
  String? _buyingSupplierTypeIdsCacheKey;
  List<String>? _buyingSupplierTypeIdsCache;
  PurchasingFilterState filterState;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.warehouses,
  ];

  FrappeService get frappeService => appState.frappeService;
  List<WarehouseInfo> get warehouses => appState.warehouses;
  int get buyingPeriodYear => filterState.buyingPeriodYear;
  int get buyingPeriodMonth => filterState.buyingPeriodMonth;

  List<PurchaseReceipt> get purchaseReceipts => _purchaseReceipts;
  bool get isPurchaseReceiptsLoading => _isPurchaseReceiptsLoading;
  bool get isMorePurchaseReceiptsLoading => _isMorePurchaseReceiptsLoading;
  bool get hasMorePurchaseReceipts => _hasMorePurchaseReceipts;
  String? get purchaseReceiptsError => _purchaseReceiptsError;

  void updateFilterState(PurchasingFilterState value) {
    filterState = value;
  }

  Future<void> refreshPurchaseReceipts() {
    final inFlight = _purchaseReceiptsFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchPurchaseReceipts();
    _purchaseReceiptsFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_purchaseReceiptsFetchInFlight, request)) {
        _purchaseReceiptsFetchInFlight = null;
      }
    });
  }

  Future<void> refreshWarehouses() => appState.refreshWarehouses();

  Future<void> loadMorePurchaseReceipts() async {
    if (_isPurchaseReceiptsLoading ||
        _isMorePurchaseReceiptsLoading ||
        !_hasMorePurchaseReceipts) {
      return;
    }

    _isMorePurchaseReceiptsLoading = true;
    final version = _purchaseReceiptQueryVersion;
    notifyListeners();

    try {
      final page = await _fetchPurchaseReceiptPage(
        limitStart: _purchaseReceipts.length,
      );
      if (version != _purchaseReceiptQueryVersion) return;
      final ids = _purchaseReceipts.map((receipt) => receipt.id).toSet();
      _purchaseReceipts = [
        ..._purchaseReceipts,
        ...page.where((receipt) => ids.add(receipt.id)),
      ];
      _hasMorePurchaseReceipts = page.length >= _documentPageSize;
      _purchaseReceiptsError = null;
    } catch (error) {
      if (version != _purchaseReceiptQueryVersion) return;
      _purchaseReceiptsError = error.toString();
    } finally {
      if (version == _purchaseReceiptQueryVersion) {
        _isMorePurchaseReceiptsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setPurchaseReceiptQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _purchaseReceiptSearch;
    final nextStatus = status;
    if (_purchaseReceiptSearch == nextSearch &&
        _purchaseReceiptStatus == nextStatus) {
      return;
    }
    _purchaseReceiptSearch = nextSearch;
    _purchaseReceiptStatus = nextStatus;
    _purchaseReceiptsFetchInFlight = null;
    await refreshPurchaseReceipts();
  }

  Future<PurchaseReceipt> loadPurchaseReceiptDetail(String id) async {
    await appState.frappeService.ensureLoggedIn();
    final doc = await appState.frappeService.fetchDocument(
      'Purchase Receipt',
      id,
    );
    final receipt = PurchaseReceipt.fromJson(doc);
    _replacePurchaseReceiptSnapshot(receipt);
    return receipt;
  }

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    if (doctype == 'Purchase Receipt') {
      await refreshPurchaseReceipts();
    }
  }

  Future<List<String>> fetchNamingSeries(String doctype) {
    return appState.fetchNamingSeries(doctype);
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    return appState.preferredWarehouse(options);
  }

  Future<void> createPurchaseReceipt({
    required String supplier,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required String namingSeries,
    required String warehouse,
    required DateTime postingDate,
    double? rate,
    String? company,
  }) async {
    await appState.createPurchaseReceipt(
      supplier: supplier,
      itemCode: itemCode,
      qty: qty,
      items: items,
      namingSeries: namingSeries,
      warehouse: warehouse,
      postingDate: postingDate,
      rate: rate,
      company: company,
    );
    await refreshPurchaseReceipts();
  }

  Future<void> uploadAttachment({
    required String doctype,
    required String documentName,
    required String filePath,
  }) async {
    await appState.frappeService.uploadFile(
      doctype: doctype,
      documentName: documentName,
      filePath: filePath,
    );
  }

  Future<List<Map<String, dynamic>>> fetchDocumentAttachments({
    required String doctype,
    required String documentName,
  }) async {
    return appState.frappeService.fetchResource(
      'File',
      fields: const ['name', 'file_name', 'file_url', 'creation'],
      filters: [
        ['attached_to_doctype', '=', doctype],
        ['attached_to_name', '=', documentName],
      ],
      orderBy: 'creation desc',
      limit: 50,
    );
  }

  Future<List<QualityInspectionRecord>> fetchQualityInspectionsForReceipt(
    String receiptId,
  ) async {
    await appState.frappeService.ensureLoggedIn();
    final rows = await appState.frappeService.fetchResource(
      'Quality Inspection',
      fields: const [
        'name',
        'item_code',
        'item_name',
        'inspection_type',
        'reference_type',
        'reference_name',
        'inspected_by',
        'status',
        'remarks',
        'report_date',
        'docstatus',
      ],
      filters: [
        ['inspection_type', '=', 'Incoming'],
        ['reference_type', '=', 'Purchase Receipt'],
        ['reference_name', '=', receiptId],
      ],
      orderBy: 'report_date desc, modified desc',
      limit: 200,
    );
    return rows.map(QualityInspectionRecord.fromJson).toList();
  }

  Future<QualityInspectionRecord> createIncomingQualityInspection({
    required String purchaseReceiptId,
    required String itemCode,
    required String status,
    String remarks = '',
    String? inspectedBy,
    DateTime? reportDate,
  }) async {
    await appState.frappeService.ensureLoggedIn();
    final payload = <String, dynamic>{
      'inspection_type': 'Incoming',
      'reference_type': 'Purchase Receipt',
      'reference_name': purchaseReceiptId,
      'item_code': itemCode,
      'status': status,
      'report_date': DateRangePresets.toFrappeDate(
        reportDate ?? DateTime.now(),
      ),
      if (inspectedBy?.trim().isNotEmpty == true)
        'inspected_by': inspectedBy!.trim(),
      if (remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
    };

    final created = await appState.frappeService.createDocument(
      'Quality Inspection',
      payload,
    );
    return QualityInspectionRecord.fromJson(created);
  }

  Future<void> _fetchPurchaseReceipts() async {
    if (appState.isSampleMode) {
      _purchaseReceipts = appState.purchaseReceipts;
      _purchaseReceiptsError = null;
      notifyListeners();
      return;
    }

    _isPurchaseReceiptsLoading = true;
    _purchaseReceiptsError = null;
    _hasMorePurchaseReceipts = true;
    _isMorePurchaseReceiptsLoading = false;
    final version = ++_purchaseReceiptQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final docs = await _fetchPurchaseReceiptPage(limitStart: 0);
      if (version != _purchaseReceiptQueryVersion) return;
      _purchaseReceipts = docs;
      _hasMorePurchaseReceipts = docs.length >= _documentPageSize;
      _purchaseReceiptsError = null;
    } catch (error) {
      if (version != _purchaseReceiptQueryVersion) return;
      _purchaseReceiptsError = error.toString();
    } finally {
      if (version == _purchaseReceiptQueryVersion) {
        _isPurchaseReceiptsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<PurchaseReceipt>> _fetchPurchaseReceiptPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('posting_date'),
      ...?_statusFilters(_purchaseReceiptStatus),
    ];
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds();
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Purchase Receipt',
      fields: const [
        'name',
        'supplier',
        'supplier_name',
        'status',
        'docstatus',
        'posting_date',
        'grand_total',
        'total_qty',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_purchaseReceiptSearch, const [
        'name',
        'supplier',
        'supplier_name',
      ]),
    );
    return data
        .where((item) => _matchesBuyingSupplierType(item, supplierTypeIds))
        .map(PurchaseReceipt.fromJson)
        .toList();
  }

  void _replacePurchaseReceiptSnapshot(PurchaseReceipt receipt) {
    final index = _purchaseReceipts.indexWhere((item) => item.id == receipt.id);
    if (index < 0) return;
    _purchaseReceipts = List<PurchaseReceipt>.from(_purchaseReceipts)
      ..[index] = receipt;
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

  bool _matchesBuyingSupplierType(
    Map<String, dynamic> row,
    List<String>? supplierIds,
  ) {
    if (supplierIds == null) return true;
    if (supplierIds.isEmpty) return false;
    return supplierIds.contains(row['supplier']?.toString() ?? '');
  }

  Future<List<String>?> _buyingSupplierTypeSupplierIds() async {
    final type = filterState.buyingSupplierTypeFilter.trim().toLowerCase();
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
