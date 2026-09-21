import '../../models/employee_attendance.dart';
import '../../models/mobile_boot.dart';
import '../../services/frappe_service.dart';
import '../../utils/mobile_access.dart';
import '../app_state_proxy_notifier.dart';

class DashboardState extends AppStateProxyNotifier {
  DashboardState({required super.appState}) {
    startWatchingAppState();
  }

  EmployeeAttendanceSnapshot _attendance = const EmployeeAttendanceSnapshot();
  List<EmployeeCheckinLog> _checkinLogs = const [];
  bool _attendanceLoading = false;
  bool _attendancePunching = false;
  String? _attendanceError;
  String _userFullName = '';
  String? _userImageUrl;

  EmployeeAttendanceSnapshot get attendance => _attendance;
  List<EmployeeCheckinLog> get checkinLogs => _checkinLogs;
  bool get attendanceLoading => _attendanceLoading;
  bool get attendancePunching => _attendancePunching;
  String? get attendanceError => _attendanceError;
  String get userFullName => _userFullName;
  String? get userImageUrl => _userImageUrl;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.mobileBoot,
    appState.selectedSiteBaseUrl,
    appState.currentUser,
    appState.currentEmployee,
    appState.mobileAccess.enabledModules.join(','),
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
  bool get canUsePos => appState.canUsePos;
  bool get canUseStock => appState.canUseStock;
  bool get canUseWarehouse => appState.canUseWarehouse;
  bool get canUseLogistics => appState.canUseLogistics;
  bool get canUseApprovals => appState.canUseApprovals;

  Future<void> refreshAttendance() async {
    _attendanceLoading = true;
    _attendanceError = null;
    notifyListeners();
    try {
      await Future.wait([
        _loadUserIdentity(),
        appState.fetchTodayEmployeeAttendance().then((value) {
          _attendance = value;
        }),
        appState.fetchTodayEmployeeCheckinLogs().then((value) {
          _checkinLogs = value;
        }),
      ]);
    } catch (error) {
      _attendanceError = error
          .toString()
          .replaceFirst(RegExp(r'^Exception:\s*'), '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    } finally {
      _attendanceLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserIdentity() async {
    try {
      final profile = await appState.fetchCurrentUserProfile();
      _userFullName = profile['full_name']?.toString().trim() ?? '';
      _userImageUrl = _absoluteImageUrl(
        profile['user_image']?.toString().trim() ?? '',
      );
    } catch (_) {}
  }

  String? _absoluteImageUrl(String image) {
    if (image.isEmpty) return null;
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    final base = appState.selectedSiteBaseUrl.trim();
    if (base.isEmpty) return image;
    return Uri.parse(base).resolve(image).toString();
  }

  Future<void> ensureAttendanceLocation() async {
    await appState.getCurrentEmployeeCheckinLocation();
  }

  Future<void> punchAttendance(String logType, {required String photoPath}) async {
    if (_attendancePunching) return;
    _attendancePunching = true;
    _attendanceError = null;
    notifyListeners();
    try {
      _attendance = await appState.punchEmployeeAttendance(
        logType: logType,
        photoPath: photoPath,
      );
      _checkinLogs = await appState.fetchTodayEmployeeCheckinLogs();
    } catch (error) {
      _attendanceError = error
          .toString()
          .replaceFirst(RegExp(r'^Exception:\s*'), '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      rethrow;
    } finally {
      _attendancePunching = false;
      notifyListeners();
    }
  }
}
