import '../models/mobile_boot.dart';
import '../config/mobile_role_registry.dart';

export '../config/mobile_role_registry.dart' show MobileModule, MobileRole;

class MobileAccess {
  final String role;
  final MobileBoot? boot;

  final Set<String>? permissionModules;

  const MobileAccess({
    required this.role,
    this.boot,
    this.permissionModules,
  });

  bool get hasBoot => boot != null;
  String get normalizedRole => MobileRoleRegistry.normalizeRoleProfile(role);

  bool get isAdministrator => normalizedRole == MobileRole.administrator;
  bool get isDeveloper => normalizedRole == MobileRole.developer;
  bool get isCompanyAdministrator =>
      normalizedRole == MobileRole.companyAdministrator;
  bool get isDirector => normalizedRole == MobileRole.director;
  bool get isSalesUser => normalizedRole == MobileRole.sales;
  bool get isSalesManager => normalizedRole == MobileRole.salesManager;
  bool get isSpg => normalizedRole == MobileRole.spg;
  bool get isSalesArea => isSalesUser || isSalesManager;
  bool get isCollectionUser => normalizedRole == MobileRole.collection;
  bool get isPurchaseUser => normalizedRole == MobileRole.purchase;
  bool get isPurchaseManager => normalizedRole == MobileRole.purchaseManager;
  bool get isPurchaseArea => isPurchaseUser || isPurchaseManager;
  bool get isWarehouse => normalizedRole == MobileRole.warehouse;
  bool get isQualityControl => normalizedRole == MobileRole.qualityControl;
  bool get isLogistics => normalizedRole == MobileRole.logistics;
  bool get isDriver => normalizedRole == MobileRole.driver;
  bool get isFinance => normalizedRole == MobileRole.finance;
  bool get isAccounting => normalizedRole == MobileRole.accounting;
  bool get isPlantationSupervisor =>
      normalizedRole == MobileRole.plantationSupervisor;
  bool get shouldScopeSalesData => isSalesUser;
  bool get canSelectAnyEmployee =>
      MobileRoleRegistry.isFullAccessRole(normalizedRole);

  bool canUse(String module) {
    final normalized = module.trim().toLowerCase();
    return enabledModules.contains(normalized);
  }

  Set<String> get enabledModules {
    Set<String> modules;
    if (MobileRoleRegistry.isFullAccessRole(normalizedRole)) {
      modules = MobileRoleRegistry.fullAccessModules();
    } else if (permissionModules != null) {
      modules = {...permissionModules!, MobileModule.dashboard};
    } else {
      modules = {MobileModule.dashboard};
    }

    const locked = {MobileModule.finance, MobileModule.accounting};
    if (MobileRoleRegistry.canUseFinanceAccounting(normalizedRole)) {
      modules = {...modules, ...locked};
    } else {
      modules = modules.difference(locked);
    }
    return modules;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MobileAccess) return false;
    return normalizedRole == other.normalizedRole &&
        _sameStringSet(enabledModules, other.enabledModules) &&
        identical(boot, other.boot);
  }

  @override
  int get hashCode => Object.hash(
    normalizedRole,
    Object.hashAll(enabledModules.toList()..sort()),
    boot,
  );

  static bool _sameStringSet(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
