import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/pos/pos_state.dart';
import '../../state/selling/sales_order_state.dart';
import '../../state/selling/selling_filter_state.dart';
import '../../theme/app_colors.dart';
import '../pos/pos_invoice/create_pos_invoice_screen.dart';
import '../pos/pos_invoice/pos_invoice_panel.dart';
import '../selling/sales_order/create_sales_order_screen.dart';
import '../shared/role_main_screen.dart';
import '../warehouse/transaction/stock/stock_entry/stock_entry_kind.dart';
import '../warehouse/transaction/stock/stock_entry/stock_entry_panel.dart';
import 'consignment_overview_tab.dart';
import 'consignment_sales_order_tab.dart';
import 'consignment_stock_report_tab.dart';

class ConsignmentMainScreen extends StatefulWidget {
  const ConsignmentMainScreen({super.key});

  @override
  State<ConsignmentMainScreen> createState() => _ConsignmentMainScreenState();
}

class _ConsignmentMainScreenState extends State<ConsignmentMainScreen> {
  Future<_ConsignmentDoctypePermissions>? _permissionsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissionsFuture ??= _loadPermissions();
  }

  Future<_ConsignmentDoctypePermissions> _loadPermissions() async {
    final state = context.read<AppState>();
    final results = await Future.wait([
      state.canReadDoctype('Consigment'),
      state.canReadDoctype('Consignment'),
      state.canReadDoctype('Sales Order'),
      state.canCreateDoctype('Sales Order'),
      state.canReadDoctype('POS Invoice'),
      state.canCreateDoctype('POS Invoice'),
      state.canReadDoctype('Stock Entry'),
      state.canCreateDoctype('Stock Entry'),
      state.canReadDoctype('Warehouse'),
      state.canReadDoctype('Bin'),
    ]);

    return _ConsignmentDoctypePermissions(
      canReadConsigmentDoctype: results[0] || results[1],
      canReadSalesOrder: results[2],
      canCreateSalesOrder: results[3],
      canReadPosInvoice: results[4],
      canCreatePosInvoice: results[5],
      canReadStockEntry: results[6],
      canCreateStockEntry: results[7],
      canReadReport: results[0] ||
          results[1] ||
          results[6] ||
          results[8] ||
          results[9],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ConsignmentDoctypePermissions>(
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
        if (!permissions.hasAnyAccess) {
          return const _NoConsignmentAccessScreen();
        }
        return _buildRoleScreen(permissions);
      },
    );
  }

  Widget _buildRoleScreen(_ConsignmentDoctypePermissions permissions) {
    final entries = _buildMenuEntries(permissions);
    final indexByKey = {
      for (var index = 0; index < entries.length; index++)
        entries[index].key: index,
    };

    return RoleMainScreen(
      title: 'Consignment',
      fallbackUsername: 'Consignment',
      onInitialize: (context) async {
        await context.read<SellingFilterState>().loadSellingFilterOptions();
      },
      onTabChanged: (context, index) => _ensureEntryLoaded(context, entries[index].key),
      screensBuilder: (onMenuSelected) => entries
          .map((entry) {
            if (entry.key == 'home') {
              return ConsignmentOverviewTab(
                actions: _buildOverviewActions(
                  onMenuSelected,
                  indexByKey,
                  entries,
                ),
              );
            }
            return entry.builder();
          })
          .toList(growable: false),
      floatingActionButtonBuilder: (context, currentIndex) =>
          _buildFab(context, currentIndex, entries),
      destinations: entries.map((entry) => entry.destination).toList(),
    );
  }

  Future<void> _ensureEntryLoaded(BuildContext context, String key) async {
    switch (key) {
      case 'sales_order':
        await context.read<SalesOrderState>().refreshSalesOrders();
      case 'pos_invoice':
        await context.read<PosState>().refreshInvoices();
      default:
        break;
    }
  }

  List<ConsignmentOverviewAction> _buildOverviewActions(
    ValueChanged<int> onMenuSelected,
    Map<String, int> indexByKey,
    List<_ConsignmentMenuEntry> entries,
  ) {
    final byKey = {for (final entry in entries) entry.key: entry};

    ConsignmentOverviewAction? actionFor(
      String key,
      String label,
      String subtitle,
      IconData icon,
      Color color,
    ) {
      final index = indexByKey[key];
      final entry = byKey[key];
      if (index == null || entry == null) return null;
      return ConsignmentOverviewAction(
        key: key,
        label: label,
        subtitle: subtitle,
        icon: icon,
        color: color,
        onTap: () => onMenuSelected(index),
      );
    }

    return [
      actionFor(
        'sales_order',
        'Sales Order',
        'Order consignment',
        Icons.receipt_long_rounded,
        const Color(0xFF16A34A),
      ),
      actionFor(
        'pos_invoice',
        'POS Invoice',
        'Invoice consignment kasir',
        Icons.point_of_sale_rounded,
        const Color(0xFF2563EB),
      ),
      actionFor(
        'transfer',
        'Material Transfer',
        'Pindah stok consignment',
        Icons.swap_horiz_rounded,
        const Color(0xFF7C3AED),
      ),
      actionFor(
        'report',
        'Stock Report',
        'Consignment Stock by Customer',
        Icons.assessment_rounded,
        const Color(0xFFEA580C),
      ),
    ].whereType<ConsignmentOverviewAction>().toList(growable: false);
  }

  List<_ConsignmentMenuEntry> _buildMenuEntries(
    _ConsignmentDoctypePermissions permissions,
  ) {
    final entries = <_ConsignmentMenuEntry>[
      _ConsignmentMenuEntry(
        key: 'home',
        destination: const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        builder: () => const SizedBox.shrink(),
      ),
    ];

    if (permissions.canReadSalesOrder) {
      entries.add(
        _ConsignmentMenuEntry(
          key: 'sales_order',
          destination: const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'SO',
          ),
          builder: () => const ConsignmentSalesOrderTab(),
          canCreate: permissions.canCreateSalesOrder,
        ),
      );
    }

    if (permissions.canReadPosInvoice) {
      entries.add(
        _ConsignmentMenuEntry(
          key: 'pos_invoice',
          destination: const NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: 'POS',
          ),
          builder: () => const PosInvoicePanel(),
          canCreate: permissions.canCreatePosInvoice,
        ),
      );
    }

    if (permissions.canReadStockEntry) {
      entries.add(
        _ConsignmentMenuEntry(
          key: 'transfer',
          destination: const NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz_rounded),
            label: 'Transfer',
          ),
          builder: () => const StockEntryPanel(
            embedded: true,
            kind: StockEntryKind(
              name: 'Material Transfer',
              purpose: 'Material Transfer',
            ),
          ),
        ),
      );
    }

    if (permissions.canReadReport) {
      entries.add(
        _ConsignmentMenuEntry(
          key: 'report',
          destination: const NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment_rounded),
            label: 'Report',
          ),
          builder: () => const ConsignmentStockReportTab(),
        ),
      );
    }

    return entries;
  }

  Widget? _buildFab(
    BuildContext context,
    int currentIndex,
    List<_ConsignmentMenuEntry> entries,
  ) {
    if (currentIndex < 0 || currentIndex >= entries.length) return null;
    final entry = entries[currentIndex];
    // Transfer FAB comes from StockEntryPanel itself.
    if (!entry.canCreate || entry.key == 'home' || entry.key == 'transfer') {
      return null;
    }

    return FloatingActionButton.extended(
      heroTag: 'consignment-create-${entry.key}',
      onPressed: () => _openCreate(context, entry.key),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded),
      label: Text(_fabLabel(entry.key)),
    );
  }

  String _fabLabel(String key) {
    return switch (key) {
      'sales_order' => 'Sales Order',
      'pos_invoice' => 'POS Invoice',
      _ => 'Buat',
    };
  }

  Future<void> _openCreate(BuildContext context, String key) async {
    switch (key) {
      case 'sales_order':
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const CreateSalesOrderScreen()),
        );
        if (created == true && context.mounted) {
          await context.read<SalesOrderState>().refreshSalesOrders();
        }
      case 'pos_invoice':
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const CreatePosInvoiceScreen()),
        );
        if (created == true && context.mounted) {
          await context.read<PosState>().refreshInvoices();
        }
    }
  }
}

class _ConsignmentMenuEntry {
  final String key;
  final NavigationDestination destination;
  final Widget Function() builder;
  final bool canCreate;

  const _ConsignmentMenuEntry({
    required this.key,
    required this.destination,
    required this.builder,
    this.canCreate = false,
  });
}

class _ConsignmentDoctypePermissions {
  final bool canReadConsigmentDoctype;
  final bool canReadSalesOrder;
  final bool canCreateSalesOrder;
  final bool canReadPosInvoice;
  final bool canCreatePosInvoice;
  final bool canReadStockEntry;
  final bool canCreateStockEntry;
  final bool canReadReport;

  const _ConsignmentDoctypePermissions({
    required this.canReadConsigmentDoctype,
    required this.canReadSalesOrder,
    required this.canCreateSalesOrder,
    required this.canReadPosInvoice,
    required this.canCreatePosInvoice,
    required this.canReadStockEntry,
    required this.canCreateStockEntry,
    required this.canReadReport,
  });

  bool get hasAnyAccess =>
      canReadConsigmentDoctype ||
      canReadSalesOrder ||
      canReadPosInvoice ||
      canReadStockEntry ||
      canReadReport;
}

class _NoConsignmentAccessScreen extends StatelessWidget {
  const _NoConsignmentAccessScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tidak ada akses Consignment.\nPastikan Role Permission untuk Sales Order, POS Invoice, atau Stock Entry aktif.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.slate,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
