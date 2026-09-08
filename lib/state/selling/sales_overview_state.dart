import '../../models/sales_workspace.dart';
import '../../services/frappe_service.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class SalesOverviewState extends AppStateProxyNotifier {
  SalesOverviewState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentSalesPerson,
    appState.sellingCompanyFilter,
    appState.sellingCompanies,
    appState.sellingSalesGroups,
    appState.activeSalesVisit,
    appState.selectedSiteBaseUrl,
    appState.currentUser,
  ];

  FrappeService get frappeService => appState.frappeService;
  MobileAccess get mobileAccess => appState.mobileAccess;
  String? get currentUser => appState.currentUser;
  String get selectedSiteBaseUrl => appState.selectedSiteBaseUrl;
  String? get currentSalesPerson => appState.currentSalesPerson;
  String get sellingCompanyFilter => appState.sellingCompanyFilter;
  List<String> get sellingCompanies => appState.sellingCompanies;
  List<String> get sellingSalesGroups => appState.sellingSalesGroups;
  SalesVisit? get activeSalesVisit => appState.activeSalesVisit;
  bool get canUseSales => appState.canUseSales;
  bool get isSalesManagerRole => appState.isSalesManagerRole;

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  Future<void> loadSellingFilterOptions() {
    return appState.loadSellingFilterOptions();
  }

  Future<void> refreshDataForCurrentRole() {
    return appState.refreshDataForCurrentRole();
  }

  Future<DailySalesReport> fetchDailySalesReport({
    required String doctype,
    required DateTime from,
    required DateTime to,
    String? salesPerson,
    String? parentSalesPerson,
    String? company,
  }) {
    return appState.fetchDailySalesReport(
      doctype: doctype,
      from: from,
      to: to,
      salesPerson: salesPerson,
      parentSalesPerson: parentSalesPerson,
      company: company,
    );
  }

  Future<List<SalesPersonCustomerRanking>> fetchTopCustomersBySalesPerson({
    required DateTime from,
    required DateTime to,
    bool scopeToCurrentSales = false,
    String? salesPerson,
    String? parentSalesPerson,
    String? company,
  }) {
    return appState.fetchTopCustomersBySalesPerson(
      from: from,
      to: to,
      scopeToCurrentSales: scopeToCurrentSales,
      salesPerson: salesPerson,
      parentSalesPerson: parentSalesPerson,
      company: company,
    );
  }

  Future<List<CollectionRanking>> fetchCollectionRanking({
    required DateTime from,
    required DateTime to,
    String? filterSalesPerson,
    String? parentSalesPerson,
    String? company,
  }) {
    return appState.fetchCollectionRanking(
      from: from,
      to: to,
      filterSalesPerson: filterSalesPerson,
      parentSalesPerson: parentSalesPerson,
      company: company,
    );
  }

  Future<void> fetchSalesVisits({bool forceRefresh = false}) {
    return appState.fetchSalesVisits(forceRefresh: forceRefresh);
  }

  Future<void> checkOutSalesVisit(String visitId) {
    return appState.checkOutSalesVisit(visitId);
  }

  Future<Map<String, dynamic>> fetchCurrentUserProfile() {
    return appState.fetchCurrentUserProfile();
  }
}
