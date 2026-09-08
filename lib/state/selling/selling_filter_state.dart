import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class SellingFilterState extends AppStateProxyNotifier {
  SellingFilterState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.mobileAccess,
    appState.sellingPeriodYear,
    appState.sellingPeriodMonth,
    appState.sellingCompanyFilter,
    appState.sellingCustomerTypeFilter,
    appState.sellingCompanies,
    appState.sellingSalesGroups,
    appState.isOrderSummaryLoading,
  ];

  MobileAccess get mobileAccess => appState.mobileAccess;
  int get sellingPeriodYear => appState.sellingPeriodYear;
  int get sellingPeriodMonth => appState.sellingPeriodMonth;
  String get sellingCompanyFilter => appState.sellingCompanyFilter;
  String get sellingCustomerTypeFilter => appState.sellingCustomerTypeFilter;
  List<String> get sellingCompanies => appState.sellingCompanies;
  List<String> get sellingSalesGroups => appState.sellingSalesGroups;
  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;

  Future<void> loadSellingFilterOptions() {
    return appState.loadSellingFilterOptions();
  }

  Future<void> refreshSellingSummaries({
    bool forceRemote = false,
    String documentType = 'Sales Order',
  }) {
    return appState.refreshSellingSummaries(
      forceRemote: forceRemote,
      documentType: documentType,
    );
  }

  Future<void> setSellingPeriod({
    required int year,
    required int month,
    String? company,
    String? customerType,
    String documentType = 'Sales Order',
  }) {
    return appState.setSellingPeriod(
      year: year,
      month: month,
      company: company,
      customerType: customerType,
      documentType: documentType,
    );
  }
}
