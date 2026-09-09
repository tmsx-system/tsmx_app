import '../../models/erp_summary.dart';
import '../app_state_proxy_notifier.dart';

class PurchasingSummaryState extends AppStateProxyNotifier {
  PurchasingSummaryState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.buyingPeriodYear,
    appState.buyingPeriodMonth,
    appState.isOrderSummaryLoading,
    appState.orderSummaryError,
    appState.purchaseOrderSummary,
    appState.purchaseReceiptSummary,
    appState.purchaseInvoiceSummary,
    appState.purchaseOrderTrendPoints,
    appState.purchaseReceiptTrendPoints,
    appState.purchaseInvoiceTrendPoints,
    appState.materialRequestTrendPoints,
  ];

  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;
  String? get orderSummaryError => appState.orderSummaryError;
  int get buyingPeriodYear => appState.buyingPeriodYear;
  int get buyingPeriodMonth => appState.buyingPeriodMonth;
  DocumentSummary get purchaseOrderSummary => appState.purchaseOrderSummary;
  DocumentSummary get purchaseReceiptSummary => appState.purchaseReceiptSummary;
  DocumentSummary get purchaseInvoiceSummary => appState.purchaseInvoiceSummary;
  List<DocumentTrendPoint> get purchaseOrderTrendPoints =>
      appState.purchaseOrderTrendPoints;
  List<DocumentTrendPoint> get purchaseReceiptTrendPoints =>
      appState.purchaseReceiptTrendPoints;
  List<DocumentTrendPoint> get purchaseInvoiceTrendPoints =>
      appState.purchaseInvoiceTrendPoints;
  List<DocumentTrendPoint> get materialRequestTrendPoints =>
      appState.materialRequestTrendPoints;

  Future<void> refreshBuyingSummaries() {
    return appState.refreshBuyingSummaries();
  }
}
