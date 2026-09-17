import 'package:flutter/material.dart';

import '../../config/mobile_role_registry.dart';
import '../driver/driver_main_screen.dart';
import '../finance/finance_main_screen.dart';
import '../logistics/logistics_main_screen.dart';
import '../plantation/plantation_main_screen.dart';
import '../pos/pos_main_screen.dart';
import '../purchase/purchase_main_screen.dart';
import '../collection/collection_main_screen.dart';
import '../sales/sales_main_screen.dart';
import '../spg/spg_main_screen.dart';
import '../warehouse/warehouse_main_screen.dart';
import 'module_placeholder_screen.dart';

/// Resolves module keys to workspace screens for the dashboard launcher.
class ModuleScreenRegistry {
  ModuleScreenRegistry._();

  static List<ModuleLaunchEntry> launchEntriesFor(Set<String> enabledModules) {
    final entries = <ModuleLaunchEntry>[];

    void add(String moduleKey, {String? routeKey}) {
      if (!enabledModules.contains(moduleKey)) return;
      final meta = MobileRoleRegistry.metaFor(moduleKey);
      if (meta == null) return;
      entries.add(
        ModuleLaunchEntry(
          moduleKey: moduleKey,
          routeKey: routeKey ?? moduleKey,
          meta: meta,
          screen: build(moduleKey, routeKey: routeKey),
        ),
      );
    }

    add(MobileModule.sales);
    add(MobileModule.spg);
    add(MobileModule.collection);
    add(MobileModule.pos);
    add(MobileModule.purchase);
    add(MobileModule.stock);
    add(MobileModule.warehouse);
    add(MobileModule.qualityControl);
    add(MobileModule.logistics);
    add(MobileModule.logistics, routeKey: 'logistics.tracking');
    add(MobileModule.logistics, routeKey: 'logistics.delivery');
    add(MobileModule.finance);
    add(MobileModule.accounting);
    add(MobileModule.plantation);

    entries.sort((a, b) => a.meta.menuOrder.compareTo(b.meta.menuOrder));
    return entries;
  }

  static Widget build(String moduleKey, {String? routeKey}) {
    final key = moduleKey.trim().toLowerCase();
    final route = routeKey?.trim().toLowerCase() ?? key;
    final meta = MobileRoleRegistry.metaFor(key);

    if (meta?.isPlanned == true) {
      return ModulePlaceholderScreen(moduleKey: key);
    }

    switch (route) {
      case MobileModule.sales:
        return const SalesMainScreen();
      case MobileModule.spg:
        return const SpgMainScreen();
      case MobileModule.collection:
        return const CollectionMainScreen();
      case MobileModule.pos:
        return const PosMainScreen();
      case MobileModule.purchase:
        return const PurchaseMainScreen();
      case MobileModule.stock:
        return const WarehouseMainScreen(stockOnly: true);
      case MobileModule.warehouse:
        return const WarehouseMainScreen();
      case MobileModule.qualityControl:
        return const WarehouseMainScreen(qualityOnly: true);
      case MobileModule.logistics:
        return const LogisticsMainScreen();
      case 'logistics.tracking':
        return const LogisticsMainScreen(trackingOnly: true);
      case 'logistics.delivery':
        return const LogisticsMainScreen(deliveryOnly: true);
      case MobileModule.finance:
        return const FinanceMainScreen();
      case MobileModule.accounting:
        return const FinanceMainScreen(
          initialTabIndex: 3,
          accountingOnly: true,
        );
      case MobileModule.plantation:
        return const PlantationMainScreen();
      default:
        return ModulePlaceholderScreen(moduleKey: key);
    }
  }

  static Widget workspaceForRole(String role) {
    final normalized = MobileRoleRegistry.normalizeRoleProfile(role);
    if (normalized == MobileRole.driver) {
      return const DriverMainScreen();
    }
    return const ModulePlaceholderScreen(moduleKey: MobileModule.dashboard);
  }
}

class ModuleLaunchEntry {
  final String moduleKey;
  final String routeKey;
  final MobileModuleMeta meta;
  final Widget screen;

  const ModuleLaunchEntry({
    required this.moduleKey,
    required this.routeKey,
    required this.meta,
    required this.screen,
  });

  String get title {
    if (routeKey == 'logistics.tracking') return 'Tracking Armada';
    if (routeKey == 'logistics.delivery') return 'Delivery Monitoring';
    return meta.defaultLabel;
  }

  String get subtitle {
    if (routeKey == 'logistics.tracking') {
      return 'Pantau status perjalanan driver';
    }
    if (routeKey == 'logistics.delivery') {
      return 'Upload POD, foto, dan tanda tangan';
    }
    return meta.defaultSubtitle;
  }
}
