import '../app_state_proxy_notifier.dart';
import '../../utils/mobile_access.dart';

class AuthState extends AppStateProxyNotifier {
  AuthState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.rememberDevice,
    appState.lastAuthError,
    appState.selectedSiteName,
    appState.selectedSiteCode,
    appState.selectedSiteBaseUrl,
    appState.mobileAccess,
  ];

  bool get isAuthenticated => appState.isAuthenticated;
  bool get rememberDevice => appState.rememberDevice;
  String? get lastAuthError => appState.lastAuthError;
  String get selectedSiteName => appState.selectedSiteName;
  String get selectedSiteCode => appState.selectedSiteCode;
  String get selectedSiteBaseUrl => appState.selectedSiteBaseUrl;
  MobileAccess get mobileAccess => appState.mobileAccess;
  bool get canUseSales => appState.canUseSales;
  bool get canUseSpg => appState.canUseSpg;
  bool get canUsePurchase => appState.canUsePurchase;
  bool get canUseStock => appState.canUseStock;
  bool get canUseApprovals => appState.canUseApprovals;

  Future<bool> initApp() => appState.initApp();

  Future<List<Map<String, String>>> loadFrappeSiteHistory() {
    return appState.loadFrappeSiteHistory();
  }

  Future<bool> configureFrappeSite({required String codeOrUrl}) {
    return appState.configureFrappeSite(codeOrUrl: codeOrUrl);
  }

  Future<bool> login(String username, String password, {String? baseUrl}) {
    return appState.login(username, password, baseUrl: baseUrl);
  }

  Future<void> saveFrappeConfig({
    required String username,
    String? password,
    bool savePassword = true,
    String? baseUrl,
    String? siteCode,
    String? siteName,
  }) {
    return appState.saveFrappeConfig(
      username: username,
      password: password,
      savePassword: savePassword,
      baseUrl: baseUrl,
      siteCode: siteCode,
      siteName: siteName,
    );
  }

  void setRememberDevice(bool value) {
    return appState.setRememberDevice(value);
  }

  void loginSample() {
    return appState.loginSample();
  }

  Future<bool> canReadDoctype(String doctype) {
    return appState.canReadDoctype(doctype);
  }

  Future<bool> canCreateDoctype(String doctype) {
    return appState.canCreateDoctype(doctype);
  }
}
