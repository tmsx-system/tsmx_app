import '../../models/promo_request.dart';
import '../../models/sales_order_insight.dart';
import '../../services/frappe_service.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class PromoState extends AppStateProxyNotifier {
  PromoState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentSalesPerson,
    appState.sellingCompanies,
  ];

  FrappeService get frappeService => appState.frappeService;
  MobileAccess get mobileAccess => appState.mobileAccess;
  bool get isSalesUserRole => appState.isSalesUserRole;
  String? get currentSalesPerson => appState.currentSalesPerson;
  List<String> get sellingCompanies => appState.sellingCompanies;

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  Future<List<Map<String, dynamic>>> fetchPromoRequestRows({
    required List<String> fields,
    List<List<dynamic>>? filters,
  }) {
    return appState.fetchPromoRequestRows(fields: fields, filters: filters);
  }

  Future<CustomerSalesInsight> fetchCustomerSalesInsight(
    String customer, {
    String? company,
  }) {
    return appState.fetchCustomerSalesInsight(customer, company: company);
  }

  Future<ItemSalesInsight> fetchItemSalesInsight(
    String itemCode, {
    String? customer,
    String? company,
    String? priceList,
    String? currency,
    String? warehouse,
    String? customerGroup,
    DateTime? transactionDate,
    double qty = 1,
    bool ignorePricingRule = false,
  }) {
    return appState.fetchItemSalesInsight(
      itemCode,
      customer: customer,
      company: company,
      priceList: priceList,
      currency: currency,
      warehouse: warehouse,
      customerGroup: customerGroup,
      transactionDate: transactionDate,
      qty: qty,
      ignorePricingRule: ignorePricingRule,
    );
  }

  Future<Map<String, dynamic>> createPromoRequest(PromoRequestDraft draft) {
    return appState.createPromoRequest(draft);
  }
}
