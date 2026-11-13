import '../../models/sales_workspace.dart';
import '../../models/spg_workspace.dart';
import '../../services/frappe_service.dart';
import '../../services/employee_checkin_location_service.dart';
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

  Future<EmployeeCheckinLocation> getCurrentEmployeeCheckinLocation() {
    return appState.getCurrentEmployeeCheckinLocation();
  }

  double visitDistanceTo(
    CustomerVisitLocation target,
    EmployeeCheckinLocation from,
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

  Future<SpgAssignmentScope> fetchSpgAssignmentScope({
    DateTime? from,
    DateTime? to,
    bool ignoreDates = false,
  }) {
    return appState.fetchSpgAssignmentScope(
      from: from,
      to: to,
      ignoreDates: ignoreDates,
    );
  }

  Future<List<Map<String, dynamic>>> fetchSpgEmployeeChoices({
    String query = '',
    DateTime? onDate,
  }) {
    return appState.fetchSpgEmployeeChoices(query: query, onDate: onDate);
  }

  Future<List<SpgCustomerOption>> fetchSpgCustomers({String query = ''}) {
    return appState.fetchSpgCustomers(query: query);
  }

  Future<List<SpgCustomerOption>> fetchScheduledSpgCustomers({
    String query = '',
    String? employee,
    DateTime? onDate,
  }) {
    return appState.fetchScheduledSpgCustomers(
      query: query,
      employee: employee,
      onDate: onDate,
    );
  }

  Future<Map<String, dynamic>> createSpgDailyActivity({
    required String customer,
    required List<String> photoPaths,
    String? employee,
    DateTime? activityDate,
    String notes = '',
  }) {
    return appState.createSpgDailyActivity(
      customer: customer,
      photoPaths: photoPaths,
      employee: employee,
      activityDate: activityDate,
      notes: notes,
    );
  }

  Future<List<Map<String, dynamic>>> fetchSpgDailyReports({
    DateTime? from,
    DateTime? to,
    String? employee,
    String? customer,
    int? docstatus,
  }) {
    return appState.fetchSpgDailyReports(
      from: from,
      to: to,
      employee: employee,
      customer: customer,
      docstatus: docstatus,
    );
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
    DateTime? reportDate,
    String notes = '',
  }) {
    return appState.createSpgDailyReport(
      customer: customer,
      sellingItems: sellingItems,
      employee: employee,
      reportDate: reportDate,
      notes: notes,
    );
  }

  Future<void> updateSpgDailyReport({
    required String name,
    required String customer,
    required List<Map<String, dynamic>> sellingItems,
    String? employee,
    DateTime? reportDate,
    String notes = '',
  }) {
    return appState.updateSpgDailyReport(
      name: name,
      customer: customer,
      sellingItems: sellingItems,
      employee: employee,
      reportDate: reportDate,
      notes: notes,
    );
  }

  Future<void> submitSpgDailyReport(String name) {
    return appState.submitSpgDailyReport(name);
  }

  Future<bool> canWriteSpgDailyReport() =>
      appState.canWriteDoctype('SPG Daily Report');

  Future<bool> canSubmitSpgDailyReport() =>
      appState.canSubmitDoctype('SPG Daily Report');
}
