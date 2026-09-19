import 'package:flutter/material.dart';

import '../../config/mobile_role_registry.dart';
import '../finance/finance_main_screen.dart';
import '../logistics/logistics_main_screen.dart';
import '../plantation/plantation_main_screen.dart';
import '../pos/pos_main_screen.dart';
import '../buying/purchase_main_screen.dart';
import '../collection/collection_main_screen.dart';
import '../selling/sales_main_screen.dart';
import '../spg/spg_main_screen.dart';
import '../warehouse/warehouse_main_screen.dart';
import 'module_placeholder_screen.dart';

/// Resolves module keys to workspace screens for the dashboard launcher.
class ModuleScreenRegistry {
  ModuleScreenRegistry._();

  static List<ModuleLaunchEntry> launchEntriesFor(Set<String> enabledModules) {
    final entries = <ModuleLaunchEntry>[];

    void add(String moduleKey) {
      if (!enabledModules.contains(moduleKey)) return;
      final meta = MobileRoleRegistry.metaFor(moduleKey);
      if (meta == null) return;
      entries.add(
        ModuleLaunchEntry(
          moduleKey: moduleKey,
          meta: meta,
          screen: build(moduleKey),
        ),
      );
    }

    add(MobileModule.sales);
    add(MobileModule.spg);
    add(MobileModule.collection);
    add(MobileModule.pos);
    add(MobileModule.purchase);
    add(MobileModule.warehouse);
    add(MobileModule.logistics);
    add(MobileModule.finance);
    add(MobileModule.accounting);
    add(MobileModule.plantation);

    entries.sort((a, b) => a.meta.menuOrder.compareTo(b.meta.menuOrder));
    return entries;
  }

  static Widget build(String moduleKey) {
    final key = moduleKey.trim().toLowerCase();
    final meta = MobileRoleRegistry.metaFor(key);

    if (meta?.isPlanned == true) {
      return ModulePlaceholderScreen(moduleKey: key);
    }

    switch (key) {
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
      case MobileModule.warehouse:
        return const WarehouseMainScreen();
      case MobileModule.logistics:
        return const LogisticsMainScreen();
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
}

class ModuleLaunchEntry {
  final String moduleKey;
  final MobileModuleMeta meta;
  final Widget screen;

  const ModuleLaunchEntry({
    required this.moduleKey,
    required this.meta,
    required this.screen,
  });

  String get routeKey => moduleKey;
  String get title => meta.defaultLabel;
  String get subtitle => meta.defaultSubtitle;
}
