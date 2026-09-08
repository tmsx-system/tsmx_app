import '../../models/sales_invoice.dart';
import '../../models/sales_workspace.dart';
import '../app_state_proxy_notifier.dart';

class CollectionState extends AppStateProxyNotifier {
  CollectionState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentSalesPerson,
    appState.sellingPeriodYear,
    appState.sellingPeriodMonth,
    appState.sellingCompanyFilter,
    appState.sellingCompanies,
    appState.isOrderSummaryLoading,
  ];

  int get sellingPeriodYear => appState.sellingPeriodYear;
  int get sellingPeriodMonth => appState.sellingPeriodMonth;
  String get sellingCompanyFilter => appState.sellingCompanyFilter;
  List<String> get sellingCompanies => appState.sellingCompanies;
  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  Future<void> setSellingPeriod({
    required int year,
    required int month,
    String? company,
    String? customerType,
    String documentType = 'Sales Invoice',
  }) {
    return appState.setSellingPeriod(
      year: year,
      month: month,
      company: company,
      customerType: customerType,
      documentType: documentType,
    );
  }

  Future<List<SalesInvoice>> fetchCollectionOutstandingInvoices() {
    return appState.fetchCollectionOutstandingInvoices();
  }

  Future<Map<String, List<SalesInvoicePaymentAllocation>>>
  fetchSalesInvoicePaymentAllocations(Iterable<String> invoiceIds) {
    return appState.fetchSalesInvoicePaymentAllocations(invoiceIds);
  }

  Future<List<CollectionPayment>> fetchCollectionPayments({
    required DateTime from,
    required DateTime to,
  }) {
    return appState.fetchCollectionPayments(from: from, to: to);
  }
}
