import '../../models/sales_workspace.dart';
import '../../models/spg_workspace.dart';
import '../../services/sales_visit_location_service.dart';
import '../app_state_proxy_notifier.dart';

class VisitState extends AppStateProxyNotifier {
  VisitState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentEmployee,
    appState.currentSalesPerson,
    appState.activeSalesVisit,
    appState.activeSpgVisit,
    appState.latestVisitLocation,
  ];

  SalesVisit? get activeSalesVisit => appState.activeSalesVisit;
  SalesVisit? get activeSpgVisit => appState.activeSpgVisit;
  VisitLocationPoint? get latestVisitLocation => appState.latestVisitLocation;

  Future<List<SalesCustomerOption>> fetchSalesCustomers() {
    return appState.fetchSalesCustomers();
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

  Future<List<SalesVisit>> fetchSalesVisits({bool forceRefresh = false}) async {
    final visits = await appState.fetchSalesVisits(forceRefresh: forceRefresh);
    notifyListeners();
    return visits;
  }

  Future<List<SalesVisit>> fetchSpgVisits({bool forceRefresh = false}) async {
    final visits = await appState.fetchSpgVisits(forceRefresh: forceRefresh);
    notifyListeners();
    return visits;
  }

  Future<CustomerVisitLocation> fetchCustomerVisitLocation(String customer) {
    return appState.fetchCustomerVisitLocation(customer);
  }

  Future<VisitLocationPoint> getCurrentVisitLocation() async {
    final point = await appState.getCurrentVisitLocation();
    notifyListeners();
    return point;
  }

  double visitDistanceTo(
    CustomerVisitLocation target,
    VisitLocationPoint from,
  ) {
    return appState.visitDistanceTo(target, from);
  }

  Future<SalesVisit> checkInSalesCustomer({
    required String customer,
    required CustomerVisitLocation target,
    required String photoPath,
  }) async {
    final visit = await appState.checkInSalesCustomer(
      customer: customer,
      target: target,
      photoPath: photoPath,
    );
    notifyListeners();
    return visit;
  }

  Future<void> checkOutSalesVisit(String visitId) async {
    await appState.checkOutSalesVisit(visitId);
    notifyListeners();
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
}
