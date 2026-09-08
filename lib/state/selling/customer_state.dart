import '../../models/inactive_customer.dart';
import '../../models/sales_order_insight.dart';
import '../../models/sales_workspace.dart';
import '../app_state_proxy_notifier.dart';

class CustomerState extends AppStateProxyNotifier {
  CustomerState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentSalesPerson,
    appState.inactiveCustomers,
    appState.isInactiveCustomersLoading,
    appState.inactiveCustomersError,
    appState.inactiveCustomersDays,
  ];

  List<InactiveCustomer> get inactiveCustomers => appState.inactiveCustomers;
  bool get isInactiveCustomersLoading => appState.isInactiveCustomersLoading;
  String? get inactiveCustomersError => appState.inactiveCustomersError;
  int get inactiveCustomersDays => appState.inactiveCustomersDays;

  Future<void> refreshInactiveCustomers({
    int daysSinceLastOrder = 60,
    List<String> doctypes = const ['Sales Order'],
    bool forceRemote = false,
  }) {
    return appState.refreshInactiveCustomers(
      daysSinceLastOrder: daysSinceLastOrder,
      doctypes: doctypes,
      forceRemote: forceRemote,
    );
  }

  Future<List<SalesCustomerOption>> fetchSalesCustomers() {
    return appState.fetchSalesCustomers();
  }

  Future<CustomerSalesInsight> fetchCustomerSalesInsight(
    String customer, {
    String? company,
  }) {
    return appState.fetchCustomerSalesInsight(customer, company: company);
  }

  Future<List<CustomerItemPrice>> fetchCustomerItemPrices({
    required String customer,
    String query = '',
    int limit = 100,
    String? company,
  }) {
    return appState.fetchCustomerItemPrices(
      customer: customer,
      query: query,
      limit: limit,
      company: company,
    );
  }
}
