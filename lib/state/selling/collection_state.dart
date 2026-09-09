import '../../models/sales_invoice.dart';
import '../../models/sales_workspace.dart';
import '../app_state_proxy_notifier.dart';
import 'selling_filter_state.dart';

class CollectionState extends AppStateProxyNotifier {
  CollectionState({required super.appState, required this.filterState}) {
    startWatchingAppState();
  }

  SellingFilterState filterState;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentSalesPerson,
    appState.sellingCompanies,
  ];

  int get sellingPeriodYear => filterState.sellingPeriodYear;
  int get sellingPeriodMonth => filterState.sellingPeriodMonth;
  String get sellingCompanyFilter => filterState.sellingCompanyFilter;
  List<String> get sellingCompanies => filterState.sellingCompanies;

  void updateFilterState(SellingFilterState value) {
    filterState = value;
  }

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  void setSellingPeriod({
    required int year,
    required int month,
    String? company,
    String? customerType,
    String documentType = 'Sales Invoice',
  }) {
    filterState.setSellingPeriod(
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
