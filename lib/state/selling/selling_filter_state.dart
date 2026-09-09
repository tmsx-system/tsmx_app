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
  DateTime get sellingPeriodFrom => _sellingPeriodMonth == 0
      ? DateTime(_sellingPeriodYear, 1, 1)
      : DateTime(_sellingPeriodYear, _sellingPeriodMonth, 1);
  DateTime get sellingPeriodTo => _sellingPeriodMonth == 0
      ? DateTime(_sellingPeriodYear, 12, 31)
      : DateTime(_sellingPeriodYear, _sellingPeriodMonth + 1, 0);

  Future<void> loadSellingFilterOptions() {
    return appState.loadSellingFilterOptions();
  }

  void setSellingPeriod({
    required int year,
    required int month,
    String? company,
    String? customerType,
    String documentType = 'Sales Order',
  }) {
    _sellingPeriodYear = year;
    _sellingPeriodMonth = month;
    _sellingCompanyFilter = company?.trim() ?? '';
    _sellingCustomerTypeFilter = customerType?.trim() ?? 'All';
    notifyListeners();
    appState.updateSellingFilterSnapshot(
      year: year,
      month: month,
      company: _sellingCompanyFilter,
      customerType: _sellingCustomerTypeFilter,
    );
  }
}
