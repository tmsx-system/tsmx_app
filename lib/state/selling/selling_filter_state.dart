import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class SellingFilterState extends AppStateProxyNotifier {
  SellingFilterState({required super.appState})
    : _sellingPeriodYear = appState.sellingPeriodYear,
      _sellingPeriodMonth = appState.sellingPeriodMonth,
      _sellingCompanyFilter = appState.sellingCompanyFilter,
      _sellingCustomerTypeFilter = appState.sellingCustomerTypeFilter {
    startWatchingAppState();
  }

  int _sellingPeriodYear;
  int _sellingPeriodMonth;
  String _sellingCompanyFilter;
  String _sellingCustomerTypeFilter;

  @override
  List<Object?> get watchFields => [
    appState.mobileAccess,
    appState.sellingCompanies,
    appState.sellingSalesGroups,
  ];

  MobileAccess get mobileAccess => appState.mobileAccess;
  int get sellingPeriodYear => _sellingPeriodYear;
  int get sellingPeriodMonth => _sellingPeriodMonth;
  String get sellingCompanyFilter => _sellingCompanyFilter;
  String get sellingCustomerTypeFilter => _sellingCustomerTypeFilter;
  List<String> get sellingCompanies => appState.sellingCompanies;
  List<String> get sellingSalesGroups => appState.sellingSalesGroups;
  DateTime get sellingPeriodFrom =>
      DateTime(_sellingPeriodYear, _sellingPeriodMonth, 1);
  DateTime get sellingPeriodTo =>
      DateTime(_sellingPeriodYear, _sellingPeriodMonth + 1, 0);

  Future<void> loadSellingFilterOptions() {
    return appState.loadSellingFilterOptions();
  }

  Future<void> setSellingPeriod({
    required int year,
    required int month,
    String? company,
    String? customerType,
    String documentType = 'Sales Order',
  }) async {
    _sellingPeriodYear = year;
    _sellingPeriodMonth = month;
    _sellingCompanyFilter = company?.trim() ?? '';
    _sellingCustomerTypeFilter = customerType?.trim() ?? 'All';
    notifyListeners();
    await appState.setSellingPeriod(
      year: year,
      month: month,
      company: _sellingCompanyFilter,
      customerType: _sellingCustomerTypeFilter,
      documentType: documentType,
    );
  }
}
