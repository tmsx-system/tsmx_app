import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class PurchasingFilterState extends AppStateProxyNotifier {
  PurchasingFilterState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.mobileAccess,
    appState.canUsePurchase,
    appState.isOrderSummaryLoading,
    appState.buyingPeriodYear,
    appState.buyingPeriodMonth,
    appState.buyingCompanyFilter,
    appState.buyingSupplierTypeFilter,
    appState.buyingCompanies,
  ];

  MobileAccess get mobileAccess => appState.mobileAccess;
  bool get canUsePurchase => appState.canUsePurchase;
  bool get isOrderSummaryLoading => appState.isOrderSummaryLoading;
  int get buyingPeriodYear => appState.buyingPeriodYear;
  int get buyingPeriodMonth => appState.buyingPeriodMonth;
  String get buyingCompanyFilter => appState.buyingCompanyFilter;
  String get buyingSupplierTypeFilter => appState.buyingSupplierTypeFilter;
  List<String> get buyingCompanies => appState.buyingCompanies;

  Future<bool> canReadDoctype(String doctype) {
    return appState.canReadDoctype(doctype);
  }

  Future<bool> canCreateDoctype(String doctype) {
    return appState.canCreateDoctype(doctype);
  }

  Future<void> loadBuyingFilterOptions() => appState.loadBuyingFilterOptions();
  Future<void> refreshBuyingSummaries() => appState.refreshBuyingSummaries();
  Future<void> refreshInventory() => appState.refreshInventory();

  Future<void> setBuyingPeriod({
    required int year,
    required int month,
    String? company,
    String? supplierType,
  }) {
    return appState.setBuyingPeriod(
      year: year,
      month: month,
      company: company,
      supplierType: supplierType,
    );
  }
}
