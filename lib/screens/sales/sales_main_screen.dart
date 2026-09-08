import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth/auth_state.dart';
import '../../state/selling/sales_order_state.dart';
import '../../state/selling/selling_filter_state.dart';
import '../../state/todo/todo_state.dart';
import '../../theme/app_colors.dart';
import '../shared/role_main_screen.dart';
import '../tabs/selling_tab.dart';
import '../tabs/stock_tab.dart';
import 'sales_order/create_sales_order_screen.dart';
import 'customer/customer_request_tab.dart';
import 'overview/sales_overview_tab.dart';
import 'visit/sales_visit_tab.dart';
import '../spg/spg_main_screen.dart';

class SalesMainScreen extends StatefulWidget {
  const SalesMainScreen({super.key});

  @override
  State<SalesMainScreen> createState() => _SalesMainScreenState();
}

class _SalesMainScreenState extends State<SalesMainScreen> {
  final _orderTabIndex = ValueNotifier<int>(0);
  Future<_SalesDoctypePermissions>? _permissionsFuture;
  static const _sellingSegments = ['so', 'dn', 'si'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissionsFuture ??= _loadPermissions();
  }

  @override
  void dispose() {
    _orderTabIndex.dispose();
    super.dispose();
  }

  void _selectOrderTab(int index) {
    _orderTabIndex.value = index.clamp(0, _sellingSegments.length - 1);
  }

  void _handleSellingSegmentChanged(String segment) {
    final nextIndex = _sellingSegments.indexOf(segment);
    if (nextIndex < 0 || _orderTabIndex.value == nextIndex) return;
    _orderTabIndex.value = nextIndex;
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<AuthState>().mobileAccess.isSpg) {
      return const SpgMainScreen();
    }
    return FutureBuilder<_SalesDoctypePermissions>(
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

  Widget _buildRoleScreen(_SalesDoctypePermissions permissions) {
    final sellingSegments = permissions.sellingSegments;
    final entries = _buildMenuEntries(permissions, sellingSegments);
    if (entries.isEmpty) return const _NoSalesAccessScreen();

    final orderIndex = entries.indexWhere((entry) => entry.key == 'order');

    return RoleMainScreen(
      title: permissions.canReadSalesOrder ? 'Sales' : 'Collection',
      fallbackUsername: 'Salesman',
      onInitialize: (context) async {
        if (context.read<AuthState>().mobileAccess.isSalesManager) {
          await context.read<TodoState>().fetchApprovalTodos();
        }
      },
      screensBuilder: (onMenuSelected) => entries
          .map(
            (entry) => entry.builder(
              _SalesMenuRouter(
                onMenuSelected: onMenuSelected,
                entries: entries,
              ),
            ),
          )
          .toList(growable: false),
      floatingActionButtonBuilder: (context, currentIndex) =>
          _buildSalesFab(context, currentIndex, orderIndex, permissions),
      destinations: entries.map((entry) => entry.destination).toList(),
    );
  }

  List<_SalesMenuEntry> _buildMenuEntries(
    _SalesDoctypePermissions permissions,
    List<String> sellingSegments,
  ) {
    final entries = <_SalesMenuEntry>[];
    final canShowOverview =
        permissions.canReadSalesOrder && permissions.canReadSalesInvoice;
    if (canShowOverview) {
      entries.add(
        _SalesMenuEntry(
          key: 'home',
          destination: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          builder: (router) => SalesOverviewTab(
            onMenuSelected: router.selectLegacySalesIndex,
            onOrderTabSelected: _selectOrderTab,
          ),
        ),
      );
    }
    if (sellingSegments.isNotEmpty) {
      entries.add(
        _SalesMenuEntry(
          key: 'order',
          destination: const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Order',
          ),
          builder: (_) => ValueListenableBuilder<int>(
            valueListenable: _orderTabIndex,
            builder: (context, index, _) {
              final selected =
                  sellingSegments[index.clamp(0, sellingSegments.length - 1)];
              return SellingTab(
                selectedSegment: selected,
                allowedSegments: sellingSegments,
                onSegmentChanged: _handleSellingSegmentChanged,
              );
            },
          ),
        ),
      );
    }
    if (permissions.canReadStock) {
      entries.add(
        _SalesMenuEntry(
          key: 'stock',
          destination: const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Stock',
          ),
          builder: (_) => const StockTab(),
        ),
      );
    }
    if (permissions.canReadCustomer) {
      entries.add(
        _SalesMenuEntry(
          key: 'customer',
          destination: const NavigationDestination(
            icon: Icon(Icons.groups_2_outlined),
            selectedIcon: Icon(Icons.groups_2_rounded),
            label: 'Customer',
          ),
          builder: (_) => const CustomerRequestTab(),
        ),
      );
    }
    if (permissions.canUseSalesVisit) {
      entries.add(
        _SalesMenuEntry(
          key: 'visit',
          destination: const NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on_rounded),
            label: 'Absensi',
          ),
          builder: (_) => const SalesVisitTab(showCheckIn: false),
        ),
      );
    }
    return entries;
  }

  Future<_SalesDoctypePermissions> _loadPermissions() async {
    final state = context.read<AuthState>();
    if (state.mobileAccess.isAdministrator ||
        state.mobileAccess.isDeveloper ||
        state.mobileAccess.isCompanyAdministrator ||
        state.mobileAccess.isDirector) {
      return _SalesDoctypePermissions.fullAccess();
    }
    final results = await Future.wait([
      state.canReadDoctype('Sales Order'),
      state.canCreateDoctype('Sales Order'),
      state.canReadDoctype('Delivery Note'),
      state.canReadDoctype('Sales Invoice'),
      state.canReadDoctype('Customer'),
      state.canReadDoctype('Sales Visit'),
      state.canCreateDoctype('Sales Visit'),
      state.canReadDoctype('Employee Checkin'),
      state.canCreateDoctype('Employee Checkin'),
      state.canReadDoctype('Bin'),
    ]);
    final permissions = _SalesDoctypePermissions(
      canReadSalesOrder: results[0],
      canCreateSalesOrder: results[1],
      canReadDeliveryNote: results[2],
      canReadSalesInvoice: results[3],
      canReadCustomer: results[4],
      canReadSalesVisit: results[5],
      canCreateSalesVisit: results[6],
      canReadEmployeeCheckin: results[7],
      canCreateEmployeeCheckin: results[8],
      canReadStock: results[9],
    );
    if (!permissions.hasAnyAccess && state.canUseSales) {
      return _SalesDoctypePermissions.legacyModuleAccess(
        collectionOnly: state.mobileAccess.isCollectionUser,
      );
    }
    return permissions;
  }

  Widget? _buildSalesFab(
    BuildContext context,
    int currentIndex,
    int orderIndex,
    _SalesDoctypePermissions permissions,
  ) {
    if (orderIndex < 0 || currentIndex != orderIndex) return null;
    if (!permissions.canCreateSalesOrder) return null;
    return ValueListenableBuilder<int>(
      valueListenable: _orderTabIndex,
      builder: (context, orderTabIndex, _) {
        if (orderTabIndex != 0) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 10,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          onPressed: () => _openCreateSalesOrder(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Buat SO',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        );
      },
    );
  }

  Future<void> _openCreateSalesOrder(BuildContext context) async {
    final salesOrderState = context.read<SalesOrderState>();
    final sellingFilterState = context.read<SellingFilterState>();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateSalesOrderScreen()));
    if (!context.mounted) return;
    await Future.wait([
      salesOrderState.refreshSalesOrders(),
      sellingFilterState.refreshSellingSummaries(documentType: 'Sales Order'),
    ]);
  }
}

class _SalesDoctypePermissions {
  final bool canReadSalesOrder;
  final bool canCreateSalesOrder;
  final bool canReadDeliveryNote;
  final bool canReadSalesInvoice;
  final bool canReadCustomer;
  final bool canReadSalesVisit;
  final bool canCreateSalesVisit;
  final bool canReadEmployeeCheckin;
  final bool canCreateEmployeeCheckin;
  final bool canReadStock;

  const _SalesDoctypePermissions({
    required this.canReadSalesOrder,
    required this.canCreateSalesOrder,
    required this.canReadDeliveryNote,
    required this.canReadSalesInvoice,
    required this.canReadCustomer,
    required this.canReadSalesVisit,
    required this.canCreateSalesVisit,
    required this.canReadEmployeeCheckin,
    required this.canCreateEmployeeCheckin,
    required this.canReadStock,
  });

  factory _SalesDoctypePermissions.fullAccess() {
    return const _SalesDoctypePermissions(
      canReadSalesOrder: true,
      canCreateSalesOrder: true,
      canReadDeliveryNote: true,
      canReadSalesInvoice: true,
      canReadCustomer: true,
      canReadSalesVisit: true,
      canCreateSalesVisit: true,
      canReadEmployeeCheckin: true,
      canCreateEmployeeCheckin: true,
      canReadStock: true,
    );
  }

  factory _SalesDoctypePermissions.legacyModuleAccess({
    required bool collectionOnly,
  }) {
    if (collectionOnly) {
      return const _SalesDoctypePermissions(
        canReadSalesOrder: false,
        canCreateSalesOrder: false,
        canReadDeliveryNote: false,
        canReadSalesInvoice: true,
        canReadCustomer: true,
        canReadSalesVisit: false,
        canCreateSalesVisit: false,
        canReadEmployeeCheckin: false,
        canCreateEmployeeCheckin: false,
        canReadStock: false,
      );
    }
    return _SalesDoctypePermissions.fullAccess();
  }

  List<String> get sellingSegments => [
    if (canReadSalesOrder) 'so',
    if (canReadDeliveryNote) 'dn',
    if (canReadSalesInvoice) 'si',
  ];

  bool get canUseSalesVisit =>
      canReadSalesVisit ||
      canCreateSalesVisit ||
      canReadEmployeeCheckin ||
      canCreateEmployeeCheckin;

  bool get hasAnyAccess =>
      canReadSalesOrder ||
      canReadDeliveryNote ||
      canReadSalesInvoice ||
      canReadCustomer ||
      canReadStock ||
      canUseSalesVisit;
}

class _SalesMenuEntry {
  final String key;
  final NavigationDestination destination;
  final Widget Function(_SalesMenuRouter router) builder;

  const _SalesMenuEntry({
    required this.key,
    required this.destination,
    required this.builder,
  });
}

class _SalesMenuRouter {
  final ValueChanged<int> onMenuSelected;
  final List<_SalesMenuEntry> entries;

  const _SalesMenuRouter({required this.onMenuSelected, required this.entries});

  void selectLegacySalesIndex(int legacyIndex) {
    final key = switch (legacyIndex) {
      1 => 'order',
      2 => 'stock',
      3 => 'customer',
      4 => 'visit',
      _ => 'home',
    };
    final index = entries.indexWhere((entry) => entry.key == key);
    if (index >= 0) onMenuSelected(index);
  }
}

class _NoSalesAccessScreen extends StatelessWidget {
  const _NoSalesAccessScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Tidak ada akses Sales yang tersedia untuk user ini.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.slate,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
