import '../../models/sales_workspace.dart';
import '../../models/spg_workspace.dart';
import '../../services/frappe_service.dart';
import '../../services/sales_visit_location_service.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class SpgState extends AppStateProxyNotifier {
  SpgState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.mobileBoot,
    appState.currentEmployee,
    appState.currentSalesPerson,
    appState.activeSpgVisit,
    appState.selectedSiteBaseUrl,
  ];

  FrappeService get frappeService => appState.frappeService;
  MobileAccess get mobileAccess => appState.mobileAccess;
  SalesVisit? get activeSpgVisit => appState.activeSpgVisit;
  String get selectedSiteBaseUrl => appState.selectedSiteBaseUrl;

  Future<Map<String, dynamic>> fetchCurrentUserProfile() {
    return appState.fetchCurrentUserProfile();
  }

  Future<CustomerVisitLocation> fetchCustomerVisitLocation(String customer) {
    return appState.fetchCustomerVisitLocation(customer);
  }

  Future<VisitLocationPoint> getCurrentVisitLocation() {
    return appState.getCurrentVisitLocation();
  }

  double visitDistanceTo(
    CustomerVisitLocation target,
    VisitLocationPoint from,
  ) {
    return appState.visitDistanceTo(target, from);
  }

  Future<List<SalesVisit>> fetchSpgVisits({bool forceRefresh = false}) async {
    final visits = await appState.fetchSpgVisits(forceRefresh: forceRefresh);
    notifyListeners();
    return visits;
  }

  Future<SalesVisit> checkInSpgCustomer({
    required String customer,
    required CustomerVisitLocation target,
    required String photoPath,
  }) async {
    final visit = await appState.checkInSpgCustomer(
      customer: customer,
      target: target,
      photoPath: photoPath,
    );
    notifyListeners();
    return visit;
  }

  Future<void> checkOutSpgVisit(String visitId) async {
    await appState.checkOutSpgVisit(visitId);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> fetchSpgDailyActivities({
    bool forceRefresh = false,
  }) {
    return appState.fetchSpgDailyActivities(forceRefresh: forceRefresh);
  }

  Future<Map<String, dynamic>> fetchSpgDailyActivityDetail(String name) {
    return appState.fetchSpgDailyActivityDetail(name);
  }

  Future<List<Map<String, dynamic>>> fetchEmployeeOptions({String query = ''}) {
    return appState.fetchEmployeeOptions(query: query);
  }

  Future<List<SpgCustomerOption>> fetchSpgCustomers({String query = ''}) {
    return appState.fetchSpgCustomers(query: query);
  }

  Future<List<SpgCustomerOption>> fetchScheduledSpgCustomers({
    String query = '',
    String? employee,
  }) {
    return appState.fetchScheduledSpgCustomers(
      query: query,
      employee: employee,
    );
  }

  Future<Map<String, dynamic>> createSpgDailyActivity({
    required String customer,
    required List<String> photoPaths,
    String? employee,
    String notes = '',
  }) {
    return appState.createSpgDailyActivity(
      customer: customer,
      photoPaths: photoPaths,
      employee: employee,
      notes: notes,
    );
  }

  Future<List<Map<String, dynamic>>> fetchSpgDailyReports() {
    return appState.fetchSpgDailyReports();
  }

  Future<Map<String, dynamic>> fetchSpgDailyReportDetail(String name) {
    return appState.fetchSpgDailyReportDetail(name);
  }

  Future<List<Map<String, dynamic>>> fetchSpgSellingItems(String query) {
    return appState.fetchSpgSellingItems(query);
  }

  Future<Map<String, dynamic>> createSpgDailyReport({
    required String customer,
    required List<Map<String, dynamic>> sellingItems,
    String? employee,
    String notes = '',
  }) {
    return appState.createSpgDailyReport(
      customer: customer,
      sellingItems: sellingItems,
      employee: employee,
      notes: notes,
    );
  }
}
