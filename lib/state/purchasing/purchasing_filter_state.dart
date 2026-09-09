import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class PurchasingFilterState extends AppStateProxyNotifier {
  PurchasingFilterState({required super.appState})
    : _buyingPeriodYear = appState.buyingPeriodYear,
      _buyingPeriodMonth = appState.buyingPeriodMonth,
      _buyingCompanyFilter = appState.buyingCompanyFilter,
      _buyingSupplierTypeFilter = appState.buyingSupplierTypeFilter {
    startWatchingAppState();
  }

  int _buyingPeriodYear;
  int _buyingPeriodMonth;
  String _buyingCompanyFilter;
  String _buyingSupplierTypeFilter;

  @override
  List<Object?> get watchFields => [
    appState.mobileAccess,
    appState.canUsePurchase,
    appState.buyingCompanies,
  ];

  MobileAccess get mobileAccess => appState.mobileAccess;
  bool get canUsePurchase => appState.canUsePurchase;
  int get buyingPeriodYear => _buyingPeriodYear;
  int get buyingPeriodMonth => _buyingPeriodMonth;
  String get buyingCompanyFilter => _buyingCompanyFilter;
  String get buyingSupplierTypeFilter => _buyingSupplierTypeFilter;
  List<String> get buyingCompanies => appState.buyingCompanies;
  DateTime get buyingPeriodFrom =>
      DateTime(_buyingPeriodYear, _buyingPeriodMonth, 1);
  DateTime get buyingPeriodTo =>
      DateTime(_buyingPeriodYear, _buyingPeriodMonth + 1, 0);

  Future<bool> canReadDoctype(String doctype) {
    return appState.canReadDoctype(doctype);
  }

  Future<bool> canCreateDoctype(String doctype) {
    return appState.canCreateDoctype(doctype);
  }

  Future<void> loadBuyingFilterOptions() => appState.loadBuyingFilterOptions();
  Future<void> refreshInventory() => appState.refreshInventory();

  Future<void> setBuyingPeriod({
    required int year,
    required int month,
    String? company,
    String? supplierType,
  }) async {
    _buyingPeriodYear = year;
    _buyingPeriodMonth = month;
    _buyingCompanyFilter = company?.trim() ?? '';
    _buyingSupplierTypeFilter = supplierType?.trim() ?? 'All';
    notifyListeners();
    await appState.setBuyingPeriod(
      year: year,
      month: month,
      company: _buyingCompanyFilter,
      supplierType: _buyingSupplierTypeFilter,
    );
  }
}
