import '../../models/erp_summary.dart';
import '../../services/domains/selling_summary_service.dart';
import '../app_state.dart';
import '../app_state_proxy_notifier.dart';
import 'selling_filter_state.dart';

class SellingSummaryState extends AppStateProxyNotifier {
  SellingSummaryState({required super.appState, required this.filterState}) {
    _service = SellingSummaryService(frappe: appState.frappeService);
    _syncFromAppState();
    startWatchingAppState();
  }

  SellingFilterState filterState;
  late SellingSummaryService _service;
  bool _isOrderSummaryLoading = false;
  String? _orderSummaryError;
  DocumentSummary _salesOrderSummary = const DocumentSummary();
  DocumentSummary _deliveryNoteSummary = const DocumentSummary();
  DocumentSummary _salesInvoiceSummary = const DocumentSummary();
  List<DocumentTrendPoint> _salesOrderTrendPoints = const [];
  List<DocumentTrendPoint> _deliveryNoteTrendPoints = const [];
  List<DocumentTrendPoint> _salesInvoiceTrendPoints = const [];

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
  ];

  bool get isOrderSummaryLoading => _isOrderSummaryLoading;
  String? get orderSummaryError => _orderSummaryError;
  int get sellingPeriodYear => filterState.sellingPeriodYear;
  int get sellingPeriodMonth => filterState.sellingPeriodMonth;
  DocumentSummary get salesOrderSummary => _salesOrderSummary;
  DocumentSummary get deliveryNoteSummary => _deliveryNoteSummary;
  DocumentSummary get salesInvoiceSummary => _salesInvoiceSummary;
  List<DocumentTrendPoint> get salesOrderTrendPoints => _salesOrderTrendPoints;
  List<DocumentTrendPoint> get deliveryNoteTrendPoints =>
      _deliveryNoteTrendPoints;
  List<DocumentTrendPoint> get salesInvoiceTrendPoints =>
      _salesInvoiceTrendPoints;

  @override
  void updateAppState(AppState value) {
    final previousFrappe = appState.frappeService;
    super.updateAppState(value);
    if (!identical(previousFrappe, appState.frappeService)) {
      _service = SellingSummaryService(frappe: appState.frappeService);
    }
  }

  void updateFilterState(SellingFilterState value) {
    filterState = value;
  }

  Future<void> refreshSellingSummaries({
    bool forceRemote = false,
    String documentType = 'Sales Order',
  }) async {
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
        year: filterState.sellingPeriodYear,
        month: filterState.sellingPeriodMonth,
        from: filterState.sellingPeriodFrom,
        to: filterState.sellingPeriodTo,
        company: filterState.sellingCompanyFilter,
        customerType: filterState.sellingCustomerTypeFilter,
        shouldScopeSalesData: appState.mobileAccess.shouldScopeSalesData,
        resolveCurrentSalesIdentity: appState.resolveCurrentSalesIdentity,
        salesIdentityError: appState.salesIdentityError,
      );
      _applyResult(result);
    } catch (error) {
      _orderSummaryError = error.toString();
    } finally {
      _isOrderSummaryLoading = false;
      notifyListeners();
    }
  }

  void _applyResult(SellingSummaryResult result) {
    _salesOrderSummary = result.salesOrderSummary;
    _deliveryNoteSummary = result.deliveryNoteSummary;
    _salesInvoiceSummary = result.salesInvoiceSummary;
    _salesOrderTrendPoints = result.salesOrderTrendPoints;
    _deliveryNoteTrendPoints = result.deliveryNoteTrendPoints;
    _salesInvoiceTrendPoints = result.salesInvoiceTrendPoints;
    _orderSummaryError = null;
  }

  void _syncFromAppState() {
    _isOrderSummaryLoading = appState.isOrderSummaryLoading;
    _orderSummaryError = appState.orderSummaryError;
    _salesOrderSummary = appState.salesOrderSummary;
    _deliveryNoteSummary = appState.deliveryNoteSummary;
    _salesInvoiceSummary = appState.salesInvoiceSummary;
    _salesOrderTrendPoints = appState.salesOrderTrendPoints;
    _deliveryNoteTrendPoints = appState.deliveryNoteTrendPoints;
    _salesInvoiceTrendPoints = appState.salesInvoiceTrendPoints;
  }
}
