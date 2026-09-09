import '../../models/erp_summary.dart';
import '../app_state_proxy_notifier.dart';

class SellingSummaryState extends AppStateProxyNotifier {
  SellingSummaryState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.sellingPeriodYear,
    appState.sellingPeriodMonth,
    appState.isOrderSummaryLoading,
    appState.orderSummaryError,
    appState.salesOrderSummary,
    appState.deliveryNoteSummary,
    appState.salesInvoiceSummary,
    appState.salesOrderTrendPoints,
    appState.deliveryNoteTrendPoints,
    appState.salesInvoiceTrendPoints,
  ];

  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;
  String? get orderSummaryError => appState.orderSummaryError;
  int get sellingPeriodYear => appState.sellingPeriodYear;
  int get sellingPeriodMonth => appState.sellingPeriodMonth;
  DocumentSummary get salesOrderSummary => appState.salesOrderSummary;
  DocumentSummary get deliveryNoteSummary => appState.deliveryNoteSummary;
  DocumentSummary get salesInvoiceSummary => appState.salesInvoiceSummary;
  List<DocumentTrendPoint> get salesOrderTrendPoints =>
      appState.salesOrderTrendPoints;
  List<DocumentTrendPoint> get deliveryNoteTrendPoints =>
      appState.deliveryNoteTrendPoints;
  List<DocumentTrendPoint> get salesInvoiceTrendPoints =>
      appState.salesInvoiceTrendPoints;

  Future<void> refreshSellingSummaries({
    bool forceRemote = false,
    String documentType = 'Sales Order',
  }) {
    return appState.refreshSellingSummaries(
      forceRemote: forceRemote,
      documentType: documentType,
    );
  }
}
