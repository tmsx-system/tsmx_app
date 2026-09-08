import '../../models/noo_request.dart';
import '../../services/frappe_service.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class NooState extends AppStateProxyNotifier {
  NooState({required super.appState}) {
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

  Future<List<Map<String, dynamic>>> fetchNooRequestRows({
    required List<String> fields,
    List<List<dynamic>>? filters,
    String? orderBy,
  }) {
    return appState.fetchNooRequestRows(
      fields: fields,
      filters: filters,
      orderBy: orderBy,
    );
  }

  Future<Map<String, dynamic>> createNooRequest(NooRequestDraft draft) {
    return appState.createNooRequest(draft);
  }

  Future<void> updateNooRequest(String name, NooRequestDraft draft) {
    return appState.updateNooRequest(name, draft);
  }
}
