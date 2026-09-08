import '../../models/mobile_boot.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class ProfileState extends AppStateProxyNotifier {
  ProfileState({required super.appState}) {
    startWatchingAppState();
  }

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.currentUser,
    appState.selectedSiteName,
    appState.selectedSiteCode,
    appState.mobileBoot,
    appState.userRole,
    appState.currentEmployee,
    appState.currentEmployeeProfile,
    appState.currentSalesPerson,
    appState.salesIdentityError,
    appState.mobileAccess,
  ];

  bool get isAuthenticated => appState.isAuthenticated;
  String? get currentUser => appState.currentUser;
  String get userRole => appState.userRole;
  String get selectedSiteName => appState.selectedSiteName;
  String get selectedSiteCode => appState.selectedSiteCode;
  String get selectedSiteBaseUrl => appState.selectedSiteBaseUrl;
  MobileBoot? get mobileBoot => appState.mobileBoot;
  MobileAccess get mobileAccess => appState.mobileAccess;
  String? get currentEmployee => appState.currentEmployee;
  Map<String, dynamic> get currentEmployeeProfile =>
      appState.currentEmployeeProfile;
  String? get currentSalesPerson => appState.currentSalesPerson;
  String? get salesIdentityError => appState.salesIdentityError;

  Future<Map<String, dynamic>> fetchCurrentUserProfile() {
    return appState.fetchCurrentUserProfile();
  }

  Future<String> uploadCurrentUserImage(String filePath) {
    return appState.uploadCurrentUserImage(filePath);
  }

  Future<void> changeCurrentUserPassword({
    required String oldPassword,
    required String newPassword,
    bool logoutAllSessions = false,
  }) {
    return appState.changeCurrentUserPassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      logoutAllSessions: logoutAllSessions,
    );
  }

  Future<void> logout() {
    return appState.logout();
  }

  Future<void> resetLocalAppCache() {
    return appState.resetLocalAppCache();
  }

  Future<String?> resolveCurrentSalesIdentity() {
    return appState.resolveCurrentSalesIdentity();
  }
}
