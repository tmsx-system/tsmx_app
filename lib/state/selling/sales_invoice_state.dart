import '../../models/erp_summary.dart';
import '../../models/sales_invoice.dart';
import '../app_state_proxy_notifier.dart';
import 'selling_document_query_mixin.dart';

class SalesInvoiceState extends AppStateProxyNotifier
    with SellingDocumentQueryMixin {
  SalesInvoiceState({required super.appState}) {
    startWatchingAppState();
  }

  List<SalesInvoice> _salesInvoices = const [];
  bool _isSalesInvoicesLoading = false;
  bool _isMoreSalesInvoicesLoading = false;
  bool _hasMoreSalesInvoices = true;
  String? _salesInvoicesError;
  String _salesInvoiceSearch = '';
  String? _salesInvoiceStatus;
  int _salesInvoiceQueryVersion = 0;
  Future<void>? _salesInvoicesFetchInFlight;

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
    appState.isOrderSummaryLoading,
    appState.salesInvoiceTrendPoints,
  ];

  int get sellingPeriodYear => appState.sellingPeriodYear;
  int get sellingPeriodMonth => appState.sellingPeriodMonth;
  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;
  List<DocumentTrendPoint> get salesInvoiceTrendPoints =>
      appState.salesInvoiceTrendPoints;

  List<SalesInvoice> get salesInvoices => _salesInvoices;
  bool get isSalesInvoicesLoading => _isSalesInvoicesLoading;
  bool get isMoreSalesInvoicesLoading => _isMoreSalesInvoicesLoading;
  bool get hasMoreSalesInvoices => _hasMoreSalesInvoices;
  String? get salesInvoicesError => _salesInvoicesError;

  Future<void> refreshSalesInvoices() {
    final inFlight = _salesInvoicesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchSalesInvoices();
    _salesInvoicesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_salesInvoicesFetchInFlight, request)) {
        _salesInvoicesFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchSalesInvoices() async {
    if (appState.isSampleMode) {
      _salesInvoices = appState.salesInvoices;
      notifyListeners();
      return;
    }

    _isSalesInvoicesLoading = true;
    _salesInvoicesError = null;
    _hasMoreSalesInvoices = true;
    _isMoreSalesInvoicesLoading = false;
    final version = ++_salesInvoiceQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final docs = await _fetchSalesInvoicePage(limitStart: 0);
      if (version != _salesInvoiceQueryVersion) return;
      _salesInvoices = docs;
      _hasMoreSalesInvoices =
          docs.length >= SellingDocumentQueryMixin.documentPageSize;
      _salesInvoicesError = null;
    } catch (error) {
      if (version != _salesInvoiceQueryVersion) return;
      _salesInvoicesError = error.toString();
    } finally {
      if (version == _salesInvoiceQueryVersion) {
        _isSalesInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreSalesInvoices() async {
    if (_isSalesInvoicesLoading ||
        _isMoreSalesInvoicesLoading ||
        !_hasMoreSalesInvoices) {
      return;
    }
    _isMoreSalesInvoicesLoading = true;
    final version = _salesInvoiceQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchSalesInvoicePage(
        limitStart: _salesInvoices.length,
      );
      if (version != _salesInvoiceQueryVersion) return;
      final ids = _salesInvoices.map((invoice) => invoice.id).toSet();
      _salesInvoices = [
        ..._salesInvoices,
        ...page.where((invoice) => ids.add(invoice.id)),
      ];
      _hasMoreSalesInvoices =
          page.length >= SellingDocumentQueryMixin.documentPageSize;
      _salesInvoicesError = null;
    } catch (error) {
      if (version != _salesInvoiceQueryVersion) return;
      _salesInvoicesError = error.toString();
    } finally {
      if (version == _salesInvoiceQueryVersion) {
        _isMoreSalesInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setSalesInvoiceQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _salesInvoiceSearch;
    final nextStatus = status;
    if (_salesInvoiceSearch == nextSearch &&
        _salesInvoiceStatus == nextStatus) {
      return;
    }
    _salesInvoiceSearch = nextSearch;
    _salesInvoiceStatus = nextStatus;
    _salesInvoicesFetchInFlight = null;
    await refreshSalesInvoices();
  }

  Future<List<SalesInvoice>> _fetchSalesInvoicePage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ...sellingPeriodFilters('posting_date'),
      ...?statusFilters(_salesInvoiceStatus),
      ...?await salesDocumentScopeFilters(),
    ];
    final rows = await fetchResourceWithFieldFallback(
      doctype: 'Sales Invoice',
      fields: const [
        'name',
        'owner',
        'customer',
        'customer_name',
        'status',
        'docstatus',
        'posting_date',
        'due_date',
        'base_net_total',
        'net_total',
        'grand_total',
        'outstanding_amount',
      ],
      limit: SellingDocumentQueryMixin.documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: searchFilters(_salesInvoiceSearch, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );
    return rows.map(SalesInvoice.fromJson).toList();
  }

  Future<SalesInvoice> loadSalesInvoiceDetail(String id) async {
    final invoice = await appState.loadSalesInvoiceDetail(id);
    final index = _salesInvoices.indexWhere((item) => item.id == invoice.id);
    if (index >= 0) {
      _salesInvoices = List<SalesInvoice>.from(_salesInvoices)
        ..[index] = invoice;
      notifyListeners();
    }
    return invoice;
  }

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    await refreshSalesInvoices();
  }
}
