import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/warehouse/warehouse_stock_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../shared/role_main_screen.dart';
import 'inventory/warehouse_inventory_tab.dart';
import 'operation/warehouse_operations_tab.dart';
import 'overview/warehouse_overview_tab.dart';
import 'quality/warehouse_quality_tab.dart';

class WarehouseMainScreen extends StatefulWidget {
  final int initialTabIndex;
  final bool qualityOnly;
  final bool stockOnly;

  const WarehouseMainScreen({
    super.key,
    this.initialTabIndex = 0,
    this.qualityOnly = false,
    this.stockOnly = false,
  });

  @override
  State<WarehouseMainScreen> createState() => _WarehouseMainScreenState();
}

class _WarehouseMainScreenState extends State<WarehouseMainScreen> {
  Future<_WarehouseDoctypePermissions>? _permissionsFuture;
  final Set<String> _loadedTabs = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissionsFuture ??= _loadPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WarehouseDoctypePermissions>(
      future: _permissionsFuture,
      builder: (context, snapshot) {
        final permissions = snapshot.data;
        if (permissions == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        return _buildRoleScreen(permissions);
      },
    );
  }

  Widget _buildRoleScreen(_WarehouseDoctypePermissions permissions) {
    final entries = _buildMenuEntries(permissions);
    if (entries.isEmpty) return const _NoWarehouseAccessScreen();
    final initial = widget.initialTabIndex.clamp(0, entries.length - 1);

    return RoleMainScreen(
      title: widget.qualityOnly ? 'Quality Control' : 'Warehouse',
      fallbackUsername: widget.qualityOnly ? 'Quality Control' : 'Warehouse',
      initialTabIndex: initial,
      onTabChanged: (context, index) =>
          _ensureWarehouseTabLoaded(context, entries[index].key, permissions),
      screensBuilder: (onMenuSelected) => entries
          .map((entry) => entry.builder(onMenuSelected))
          .toList(growable: false),
      destinations: entries.map((entry) => entry.destination).toList(),
    );
  }

  Future<void> _ensureWarehouseTabLoaded(
    BuildContext context,
    String key,
    _WarehouseDoctypePermissions permissions,
  ) async {
    if (!_loadedTabs.add(key)) return;
    final state = context.read<WarehouseStockState>();
    switch (key) {
      case 'home':
        await Future.wait([
          if (permissions.canReadWarehouse && state.warehouses.isEmpty)
            state.refreshWarehouses(),
          if (permissions.canReadStock && state.inventory.isEmpty)
            state.refreshInventory(),
        ]);
        break;
      case 'ops':
        if (permissions.canReadWarehouse && state.warehouses.isEmpty) {
          await state.refreshWarehouses();
        }
        break;
      case 'stock':
      case 'qc':
        break;
    }
  }

  List<_WarehouseMenuEntry> _buildMenuEntries(
    _WarehouseDoctypePermissions permissions,
  ) {
    final entries = <_WarehouseMenuEntry>[];
    if (!widget.qualityOnly && !widget.stockOnly && permissions.canShowHome) {
      entries.add(
        _WarehouseMenuEntry(
          key: 'home',
          destination: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          builder: (onMenuSelected) =>
              WarehouseOverviewTab(onMenuSelected: onMenuSelected),
        ),
      );
    }
    if (!widget.qualityOnly && !widget.stockOnly && permissions.canUseOps) {
      entries.add(
        const _WarehouseMenuEntry(
          key: 'ops',
          destination: NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz_rounded),
            label: 'Operasi',
          ),
          builder: _operationsTab,
        ),
      );
    }
    if (!widget.qualityOnly && permissions.canReadStock) {
      entries.add(
        const _WarehouseMenuEntry(
          key: 'stock',
          destination: NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Stok',
          ),
          builder: _inventoryTab,
        ),
      );
    }
    if (!widget.stockOnly && permissions.canReadQualityInspection) {
      entries.add(
        const _WarehouseMenuEntry(
          key: 'qc',
          destination: NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'QC',
          ),
          builder: _qualityTab,
        ),
      );
    }
    return entries;
  }

  Future<_WarehouseDoctypePermissions> _loadPermissions() async {
    final state = context.read<WarehouseStockState>();
    final access = state.appState.mobileAccess;
    if (access.isAdministrator ||
        access.isDeveloper ||
        access.isCompanyAdministrator ||
        access.isDirector) {
      return _WarehouseDoctypePermissions.fullAccess();
    }
    final results = await Future.wait([
      state.canReadDoctype('Warehouse'),
      state.canReadDoctype('Bin'),
      state.canReadDoctype('Stock Ledger Entry'),
      state.canReadDoctype('Stock Entry'),
      state.canCreateDoctype('Stock Entry'),
      state.canReadDoctype('Stock Reconciliation'),
      state.canCreateDoctype('Stock Reconciliation'),
      state.canReadDoctype('Quality Inspection'),
      state.canCreateDoctype('Quality Inspection'),
    ]);
    final permissions = _WarehouseDoctypePermissions(
      canReadWarehouse: results[0],
      canReadBin: results[1],
      canReadStockLedger: results[2],
      canReadStockEntry: results[3],
      canCreateStockEntry: results[4],
      canReadStockReconciliation: results[5],
      canCreateStockReconciliation: results[6],
      canReadQualityInspection: results[7],
      canCreateQualityInspection: results[8],
    );
    if (!permissions.hasAnyAccess &&
        (state.appState.canUseWarehouse ||
            state.appState.canUseStock ||
            state.appState.canUseQualityControl)) {
      return _WarehouseDoctypePermissions.legacyModuleAccess(
        stockOnly: widget.stockOnly,
        qualityOnly: widget.qualityOnly,
      );
    }
    return permissions;
  }
}

Widget _operationsTab(ValueChanged<int> _) => const WarehouseOperationsTab();
Widget _inventoryTab(ValueChanged<int> _) => const WarehouseInventoryTab();
Widget _qualityTab(ValueChanged<int> _) => const WarehouseQualityTab();

class _WarehouseDoctypePermissions {
  final bool canReadWarehouse;
  final bool canReadBin;
  final bool canReadStockLedger;
  final bool canReadStockEntry;
  final bool canCreateStockEntry;
  final bool canReadStockReconciliation;
  final bool canCreateStockReconciliation;
  final bool canReadQualityInspection;
  final bool canCreateQualityInspection;

  const _WarehouseDoctypePermissions({
    required this.canReadWarehouse,
    required this.canReadBin,
    required this.canReadStockLedger,
    required this.canReadStockEntry,
    required this.canCreateStockEntry,
    required this.canReadStockReconciliation,
    required this.canCreateStockReconciliation,
    required this.canReadQualityInspection,
    required this.canCreateQualityInspection,
  });

  factory _WarehouseDoctypePermissions.fullAccess() {
    return const _WarehouseDoctypePermissions(
      canReadWarehouse: true,
      canReadBin: true,
      canReadStockLedger: true,
      canReadStockEntry: true,
      canCreateStockEntry: true,
      canReadStockReconciliation: true,
      canCreateStockReconciliation: true,
      canReadQualityInspection: true,
      canCreateQualityInspection: true,
    );
  }

  factory _WarehouseDoctypePermissions.legacyModuleAccess({
    required bool stockOnly,
    required bool qualityOnly,
  }) {
    if (qualityOnly) {
      return const _WarehouseDoctypePermissions(
        canReadWarehouse: false,
        canReadBin: false,
        canReadStockLedger: false,
        canReadStockEntry: false,
        canCreateStockEntry: false,
        canReadStockReconciliation: false,
        canCreateStockReconciliation: false,
        canReadQualityInspection: true,
        canCreateQualityInspection: true,
      );
    }
    if (stockOnly) {
      return const _WarehouseDoctypePermissions(
        canReadWarehouse: true,
        canReadBin: true,
        canReadStockLedger: true,
        canReadStockEntry: false,
        canCreateStockEntry: false,
        canReadStockReconciliation: false,
        canCreateStockReconciliation: false,
        canReadQualityInspection: false,
        canCreateQualityInspection: false,
      );
    }
    return _WarehouseDoctypePermissions.fullAccess();
  }

  bool get canReadStock => canReadBin || canReadStockLedger;
  bool get canUseOps =>
      canReadStockEntry ||
      canCreateStockEntry ||
      canReadStockReconciliation ||
      canCreateStockReconciliation;
  bool get canShowHome => canReadWarehouse || canReadStock || canUseOps;
  bool get hasAnyAccess =>
      canShowHome || canReadQualityInspection || canCreateQualityInspection;
}

class _WarehouseMenuEntry {
  final String key;
  final NavigationDestination destination;
  final Widget Function(ValueChanged<int> onMenuSelected) builder;

  const _WarehouseMenuEntry({
    required this.key,
    required this.destination,
    required this.builder,
  });
}

class _NoWarehouseAccessScreen extends StatelessWidget {
  const _NoWarehouseAccessScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: TmsxResponsiveBody(
        maxWidth: 520,
        child: Padding(
          padding: EdgeInsets.all(TmsxResponsive.horizontalPadding(context)),
          child: const Text(
            'Tidak ada akses Warehouse/Stock/QC yang tersedia untuk user ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}
