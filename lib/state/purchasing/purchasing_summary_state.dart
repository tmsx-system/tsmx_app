import '../../models/erp_summary.dart';
import '../../services/domains/purchasing_summary_service.dart';
import '../app_state.dart';
import '../app_state_proxy_notifier.dart';
import 'purchasing_filter_state.dart';

class PurchasingSummaryState extends AppStateProxyNotifier {
  PurchasingSummaryState({required super.appState, required this.filterState}) {
    _service = PurchasingSummaryService(frappe: appState.frappeService);
    _syncFromAppState();
    startWatchingAppState();
  }

  PurchasingFilterState filterState;
  late PurchasingSummaryService _service;
  bool _isOrderSummaryLoading = false;
  String? _orderSummaryError;
  DocumentSummary _purchaseOrderSummary = const DocumentSummary();
  DocumentSummary _purchaseReceiptSummary = const DocumentSummary();
  DocumentSummary _purchaseInvoiceSummary = const DocumentSummary();
  List<DocumentTrendPoint> _purchaseOrderTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseReceiptTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseInvoiceTrendPoints = const [];
  List<DocumentTrendPoint> _materialRequestTrendPoints = const [];

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
  ];

  bool get isOrderSummaryLoading => _isOrderSummaryLoading;
  String? get orderSummaryError => _orderSummaryError;
  int get buyingPeriodYear => filterState.buyingPeriodYear;
  int get buyingPeriodMonth => filterState.buyingPeriodMonth;
  DocumentSummary get purchaseOrderSummary => _purchaseOrderSummary;
  DocumentSummary get purchaseReceiptSummary => _purchaseReceiptSummary;
  DocumentSummary get purchaseInvoiceSummary => _purchaseInvoiceSummary;
  List<DocumentTrendPoint> get purchaseOrderTrendPoints =>
      _purchaseOrderTrendPoints;
  List<DocumentTrendPoint> get purchaseReceiptTrendPoints =>
      _purchaseReceiptTrendPoints;
  List<DocumentTrendPoint> get purchaseInvoiceTrendPoints =>
      _purchaseInvoiceTrendPoints;
  List<DocumentTrendPoint> get materialRequestTrendPoints =>
      _materialRequestTrendPoints;

  @override
  void updateAppState(AppState value) {
    final previousFrappe = appState.frappeService;
    super.updateAppState(value);
    if (!identical(previousFrappe, appState.frappeService)) {
      _service = PurchasingSummaryService(frappe: appState.frappeService);
    }
  }

  void updateFilterState(PurchasingFilterState value) {
    filterState = value;
  }

  Future<void> refreshBuyingSummaries() async {
    if (appState.isSampleMode) {
      _syncFromAppState();
      notifyListeners();
      return;
    }

    _isOrderSummaryLoading = true;
    _orderSummaryError = null;
    notifyListeners();
    try {
      final result = await _service.fetch(
        year: filterState.buyingPeriodYear,
        month: filterState.buyingPeriodMonth,
        from: filterState.buyingPeriodFrom,
        to: filterState.buyingPeriodTo,
        company: filterState.buyingCompanyFilter,
        supplierType: filterState.buyingSupplierTypeFilter,
      );
      _applyResult(result);
    } catch (error) {
      _orderSummaryError = error.toString();
    } finally {
      _isOrderSummaryLoading = false;
      notifyListeners();
    }
  }

  void _applyResult(PurchasingSummaryResult result) {
    _purchaseOrderSummary = result.purchaseOrderSummary;
    _purchaseReceiptSummary = result.purchaseReceiptSummary;
    _purchaseInvoiceSummary = result.purchaseInvoiceSummary;
    _purchaseOrderTrendPoints = result.purchaseOrderTrendPoints;
    _purchaseReceiptTrendPoints = result.purchaseReceiptTrendPoints;
    _purchaseInvoiceTrendPoints = result.purchaseInvoiceTrendPoints;
    _materialRequestTrendPoints = result.materialRequestTrendPoints;
    _orderSummaryError = null;
  }

  void _syncFromAppState() {
    _isOrderSummaryLoading = appState.isOrderSummaryLoading;
    _orderSummaryError = appState.orderSummaryError;
    _purchaseOrderSummary = appState.purchaseOrderSummary;
    _purchaseReceiptSummary = appState.purchaseReceiptSummary;
    _purchaseInvoiceSummary = appState.purchaseInvoiceSummary;
    _purchaseOrderTrendPoints = appState.purchaseOrderTrendPoints;
    _purchaseReceiptTrendPoints = appState.purchaseReceiptTrendPoints;
    _purchaseInvoiceTrendPoints = appState.purchaseInvoiceTrendPoints;
    _materialRequestTrendPoints = appState.materialRequestTrendPoints;
  }
}
