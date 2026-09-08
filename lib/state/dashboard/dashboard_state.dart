import '../../models/mobile_boot.dart';
import '../../services/frappe_service.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class DashboardState extends AppStateProxyNotifier {
  DashboardState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.mobileBoot,
    appState.selectedSiteBaseUrl,
    appState.currentUser,
  ];

  FrappeService get frappeService => appState.frappeService;
  MobileAccess get mobileAccess => appState.mobileAccess;
  MobileBoot? get mobileBoot => appState.mobileBoot;
  String get selectedSiteBaseUrl => appState.selectedSiteBaseUrl;
  String get selectedSiteName => appState.selectedSiteName;
  String? get currentUser => appState.currentUser;
  String get appDisplayName => appState.appDisplayName;
  bool get canUseSales => appState.canUseSales;
  bool get canUsePurchase => appState.canUsePurchase;
  bool get canUseStock => appState.canUseStock;
  bool get canUseWarehouse => appState.canUseWarehouse;
  bool get canUseLogistics => appState.canUseLogistics;
  bool get canUseApprovals => appState.canUseApprovals;
}
