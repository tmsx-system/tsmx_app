import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/purchasing/purchasing_filter_state.dart';
import '../../theme/app_colors.dart';
import '../shared/role_main_screen.dart';
import 'material_request/create_material_request_screen.dart';
import 'material_request/material_request_panel.dart';
import 'purchase_invoice/create_purchase_invoice_screen.dart';
import 'purchase_invoice/purchase_invoice_panel.dart';
import '../../state/purchasing/material_request_state.dart';
import '../../state/purchasing/purchase_invoice_state.dart';
import '../../state/purchasing/purchase_order_state.dart';
import '../../state/purchasing/purchase_receipt_state.dart';
import '../../state/purchasing/purchasing_summary_state.dart';
import 'purchase_order/create_purchase_order_screen.dart';
import 'purchase_order/purchase_order_panel.dart';
import 'purchase_overview_tab.dart';
import 'purchase_receipt/create_purchase_receipt_screen.dart';
import 'purchase_receipt/purchase_receipt_panel.dart';

class PurchaseMainScreen extends StatefulWidget {
  const PurchaseMainScreen({super.key});

  @override
  State<PurchaseMainScreen> createState() => _PurchaseMainScreenState();
}

class _PurchaseMainScreenState extends State<PurchaseMainScreen> {
  Future<_PurchaseDoctypePermissions>? _permissionsFuture;
  final Set<String> _loadedDoctypeKeys = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissionsFuture ??= _loadPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PurchaseDoctypePermissions>(
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

  Widget _buildRoleScreen(_PurchaseDoctypePermissions permissions) {
    final entries = _buildMenuEntries(permissions);
    if (entries.isEmpty) return const _NoPurchaseAccessScreen();
    final indexByKey = {
      for (var index = 0; index < entries.length; index++)
        entries[index].key: index,
    };

    return RoleMainScreen(
      title: 'Purchase',
      fallbackUsername: 'Purchase',
      onInitialize: (context) async {
        await context.read<PurchasingFilterState>().loadBuyingFilterOptions();
      },
      onTabChanged: (context, index) =>
          _ensureEntryLoaded(context, entries[index].key),
      screensBuilder: (onMenuSelected) => entries
          .map((entry) {
            if (entry.key == 'home') {
              return PurchaseOverviewTab(
                onMenuSelected: onMenuSelected,
                actions: _buildOverviewActions(
                  onMenuSelected,
                  indexByKey,
                  entries,
                ),
              );
            }
            return entry.builder(onMenuSelected);
          })
          .toList(growable: false),
      floatingActionButtonBuilder: (context, currentIndex) =>
          _buildPurchaseFab(context, currentIndex, entries),
      destinations: entries.map((entry) => entry.destination).toList(),
    );
  }

  Future<void> _ensureEntryLoaded(BuildContext context, String key) async {
    if (key == 'home') return;
    if (!_loadedDoctypeKeys.add(key)) return;
    await _refreshPurchaseDoctype(
      context,
      key,
      includeInventoryForMaterialRequest: true,
    );
  }

  List<PurchaseOverviewAction> _buildOverviewActions(
    ValueChanged<int> onMenuSelected,
    Map<String, int> indexByKey,
    List<_PurchaseMenuEntry> entries,
  ) {
    final byKey = {for (final entry in entries) entry.key: entry};

    PurchaseOverviewAction? actionFor(
      String key,
      String label,
      IconData icon,
      Color color,
    ) {
      final index = indexByKey[key];
      final entry = byKey[key];
      if (index == null || entry == null) return null;
      return PurchaseOverviewAction(
        key: key,
        label: label,
        icon: icon,
        color: color,
        onTap: () => onMenuSelected(index),
      );
    }

    return [
      actionFor(
        'po',
        'PO',
        Icons.shopping_bag_rounded,
        const Color(0xFF22C55E),
      ),
      actionFor(
        'pr',
        'Receipt',
        Icons.move_to_inbox_rounded,
        const Color(0xFF2563EB),
      ),
      actionFor(
        'pi',
        'Invoice',
        Icons.receipt_long_rounded,
        const Color(0xFF0891B2),
      ),
      actionFor(
        'mr',
        'Request',
        Icons.assignment_turned_in_rounded,
        const Color(0xFFF59E0B),
      ),
    ].whereType<PurchaseOverviewAction>().toList(growable: false);
  }

  List<_PurchaseMenuEntry> _buildMenuEntries(
    _PurchaseDoctypePermissions permissions,
  ) {
    final entries = <_PurchaseMenuEntry>[];
    final canShowOverview =
        permissions.canReadPurchaseOrder ||
        permissions.canReadPurchaseReceipt ||
        permissions.canReadPurchaseInvoice;

    if (canShowOverview) {
      entries.add(
        _PurchaseMenuEntry(
          key: 'home',
          destination: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          builder: (onMenuSelected) =>
              PurchaseOverviewTab(onMenuSelected: onMenuSelected),
        ),
      );
    }
    if (permissions.canReadPurchaseOrder) {
      entries.add(
        _PurchaseMenuEntry(
          key: 'po',
          destination: const NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag_rounded),
            label: 'PO',
          ),
          builder: (_) => _PurchasePane(
            doctypeKey: 'po',
            child: PurchaseOrderPanel(
              canCreatePurchaseReceipt: permissions.canCreatePurchaseReceipt,
              canCreatePurchaseInvoice: permissions.canCreatePurchaseInvoice,
            ),
          ),
          canCreate: permissions.canCreatePurchaseOrder,
        ),
      );
    }
    if (permissions.canReadPurchaseReceipt) {
      entries.add(
        _PurchaseMenuEntry(
          key: 'pr',
          destination: const NavigationDestination(
            icon: Icon(Icons.move_to_inbox_outlined),
            selectedIcon: Icon(Icons.move_to_inbox_rounded),
            label: 'Receipt',
          ),
          builder: (_) => const _PurchasePane(
            doctypeKey: 'pr',
            child: PurchaseReceiptPanel(),
          ),
          canCreate: permissions.canCreatePurchaseReceipt,
        ),
      );
    }
    if (permissions.canReadPurchaseInvoice) {
      entries.add(
        _PurchaseMenuEntry(
          key: 'pi',
          destination: const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Invoice',
          ),
          builder: (_) => const _PurchasePane(
            doctypeKey: 'pi',
            child: PurchaseInvoicePanel(),
          ),
          canCreate: permissions.canCreatePurchaseInvoice,
        ),
      );
    }
    if (permissions.canReadMaterialRequest) {
      entries.add(
        _PurchaseMenuEntry(
          key: 'mr',
          destination: const NavigationDestination(
            icon: Icon(Icons.assignment_turned_in_outlined),
            selectedIcon: Icon(Icons.assignment_turned_in_rounded),
            label: 'Request',
          ),
          builder: (_) => _PurchasePane(
            doctypeKey: 'mr',
            child: MaterialRequestPanel(
              canCreateMaterialRequest: permissions.canCreateMaterialRequest,
              canCreatePurchaseOrder: permissions.canCreatePurchaseOrder,
            ),
          ),
          canCreate: permissions.canCreateMaterialRequest,
        ),
      );
    }
    return entries;
  }

  Future<_PurchaseDoctypePermissions> _loadPermissions() async {
    final state = context.read<PurchasingFilterState>();
    if (state.mobileAccess.isAdministrator ||
        state.mobileAccess.isDeveloper ||
        state.mobileAccess.isCompanyAdministrator ||
        state.mobileAccess.isDirector) {
      return _PurchaseDoctypePermissions.fullAccess();
    }
    final results = await Future.wait([
      state.canReadDoctype('Purchase Order'),
      state.canCreateDoctype('Purchase Order'),
      state.canReadDoctype('Purchase Receipt'),
      state.canCreateDoctype('Purchase Receipt'),
      state.canReadDoctype('Purchase Invoice'),
      state.canCreateDoctype('Purchase Invoice'),
      state.canReadDoctype('Material Request'),
      state.canCreateDoctype('Material Request'),
    ]);
    final permissions = _PurchaseDoctypePermissions(
      canReadPurchaseOrder: results[0],
      canCreatePurchaseOrder: results[1],
      canReadPurchaseReceipt: results[2],
      canCreatePurchaseReceipt: results[3],
      canReadPurchaseInvoice: results[4],
      canCreatePurchaseInvoice: results[5],
      canReadMaterialRequest: results[6],
      canCreateMaterialRequest: results[7],
    );
    if (!permissions.hasAnyAccess && state.canUsePurchase) {
      return _PurchaseDoctypePermissions.legacyModuleAccess();
    }
    return permissions;
  }

  Widget? _buildPurchaseFab(
    BuildContext context,
    int currentIndex,
    List<_PurchaseMenuEntry> entries,
  ) {
    if (currentIndex < 0 || currentIndex >= entries.length) return null;
    final entry = entries[currentIndex];
    if (!entry.canCreate) return null;
    return FloatingActionButton.extended(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
      onPressed: () => _openPurchaseCreate(context, entry.key),
      icon: Icon(switch (entry.key) {
        'pr' => Icons.move_to_inbox_outlined,
        'pi' => Icons.receipt_long_outlined,
        'mr' => Icons.assignment_add,
        _ => Icons.add_shopping_cart_rounded,
      }),
      label: Text(switch (entry.key) {
        'pr' => 'Terima Barang',
        'pi' => 'Buat Invoice',
        'mr' => 'Buat Request',
        _ => 'Buat PO',
      }),
    );
  }

  Future<void> _openPurchaseCreate(BuildContext context, String key) async {
    final route = switch (key) {
      'pr' => MaterialPageRoute<void>(
        builder: (_) => const CreatePurchaseReceiptScreen(),
      ),
      'pi' => MaterialPageRoute<void>(
        builder: (_) => const CreatePurchaseInvoiceScreen(),
      ),
      'mr' => MaterialPageRoute<void>(
        builder: (_) => const CreateMaterialRequestScreen(),
      ),
      _ => MaterialPageRoute<void>(
        builder: (_) => const CreatePurchaseOrderScreen(),
      ),
    };

    await Navigator.of(context).push(route);
    if (!context.mounted) return;

    await _refreshPurchaseDoctype(context, key);
  }
}

Future<void> _refreshPurchaseDoctype(
  BuildContext context,
  String key, {
  bool includeInventoryForMaterialRequest = false,
}) async {
  switch (key) {
    case 'pr':
      await context.read<PurchaseReceiptState>().refreshPurchaseReceipts();
      break;
    case 'pi':
      await context.read<PurchaseInvoiceState>().refreshPurchaseInvoices();
      break;
    case 'mr':
      final state = context.read<MaterialRequestState>();
      await state.refreshMaterialRequests();
      if (includeInventoryForMaterialRequest && state.inventory.isEmpty) {
        await state.refreshInventory();
      }
      break;
    default:
      await context.read<PurchaseOrderState>().refreshPurchaseOrders();
      break;
  }
}

class _PurchasePane extends StatelessWidget {
  final String doctypeKey;
  final Widget child;

  const _PurchasePane({required this.doctypeKey, required this.child});

  Future<void> _openPurchasePeriodFilter(BuildContext context) async {
    final purchasingState = context.read<PurchasingFilterState>();
    final summaryState = context.read<PurchasingSummaryState>();
    final supplierType =
        _purchaseSupplierTypeOptions.containsKey(
          purchasingState.buyingSupplierTypeFilter,
        )
        ? purchasingState.buyingSupplierTypeFilter
        : 'all';

    final result = await showModalBottomSheet<_PurchasePeriodFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _PurchasePeriodFilterSheet(
        initialMonth: purchasingState.buyingPeriodMonth,
        initialYear: purchasingState.buyingPeriodYear,
        initialCompany: purchasingState.buyingCompanyFilter,
        initialSupplierType: supplierType,
        companies: purchasingState.buyingCompanies,
        loading: summaryState.isOrderSummaryLoading,
      ),
    );
    if (result == null || !context.mounted) return;

    context.read<PurchasingFilterState>().setBuyingPeriod(
      year: result.year,
      month: result.month,
      company: result.company,
      supplierType: result.supplierType,
    );
    if (!context.mounted) return;
    await Future.wait([
      context.read<PurchasingSummaryState>().refreshBuyingSummaries(),
      _refreshActiveDoctype(context),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PurchasingFilterState>();
    final summaryState = context.watch<PurchasingSummaryState>();
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _refreshActiveDoctype(context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter > 320) return false;
          _loadMoreActiveDoctype(context);
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            _PurchasePeriodFilterBar(
              selectedYear: state.buyingPeriodYear,
              selectedMonth: state.buyingPeriodMonth,
              selectedCompany: state.buyingCompanyFilter,
              selectedSupplierType: state.buyingSupplierTypeFilter,
              loading: summaryState.isOrderSummaryLoading,
              onOpenFilter: () => _openPurchasePeriodFilter(context),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _refreshActiveDoctype(BuildContext context) {
    return _refreshPurchaseDoctype(context, doctypeKey);
  }

  void _loadMoreActiveDoctype(BuildContext context) {
    switch (doctypeKey) {
      case 'pr':
        context.read<PurchaseReceiptState>().loadMorePurchaseReceipts();
        break;
      case 'pi':
        context.read<PurchaseInvoiceState>().loadMorePurchaseInvoices();
        break;
      case 'mr':
        context.read<MaterialRequestState>().loadMoreMaterialRequests();
        break;
      default:
        context.read<PurchaseOrderState>().loadMorePurchaseOrders();
        break;
    }
  }
}

const Map<String, String> _purchaseSupplierTypeOptions = {
  'all': 'Semua Supplier',
  'external': 'External',
  'internal': 'Internal',
};

class _PurchasePeriodFilterBar extends StatelessWidget {
  const _PurchasePeriodFilterBar({
    required this.selectedYear,
    required this.selectedMonth,
    required this.selectedCompany,
    required this.selectedSupplierType,
    required this.loading,
    required this.onOpenFilter,
  });

  final int selectedYear;
  final int selectedMonth;
  final String selectedCompany;
  final String selectedSupplierType;
  final bool loading;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    final periodLabel = selectedMonth == 0
        ? '$selectedYear'
        : '${_purchaseMonthName(selectedMonth)} $selectedYear';
    final companyLabel = selectedCompany.trim().isEmpty
        ? 'Semua Company'
        : selectedCompany.trim();
    final supplierLabel =
        _purchaseSupplierTypeOptions[selectedSupplierType] ?? 'Semua Supplier';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shopping_bag_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$periodLabel  |  $companyLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  supplierLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: loading ? null : onOpenFilter,
            icon: const Icon(Icons.filter_alt_rounded, size: 15),
            label: const Text('Filter'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 38),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchasePeriodFilterValue {
  const _PurchasePeriodFilterValue({
    required this.month,
    required this.year,
    required this.company,
    required this.supplierType,
  });

  final int month;
  final int year;
  final String company;
  final String supplierType;
}

class _PurchasePeriodFilterSheet extends StatefulWidget {
  const _PurchasePeriodFilterSheet({
    required this.initialMonth,
    required this.initialYear,
    required this.initialCompany,
    required this.initialSupplierType,
    required this.companies,
    required this.loading,
  });

  final int initialMonth;
  final int initialYear;
  final String initialCompany;
  final String initialSupplierType;
  final List<String> companies;
  final bool loading;

  @override
  State<_PurchasePeriodFilterSheet> createState() =>
      _PurchasePeriodFilterSheetState();
}

class _PurchasePeriodFilterSheetState
    extends State<_PurchasePeriodFilterSheet> {
  late int _month;
  late int _year;
  late String _company;
  late String _supplierType;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _year = widget.initialYear;
    _company = widget.initialCompany;
    _supplierType = widget.initialSupplierType;
  }

  void _reset() {
    final now = DateTime.now();
    setState(() {
      _month = now.month;
      _year = now.year;
      _company = '';
      _supplierType = 'all';
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _PurchasePeriodFilterValue(
        month: _month,
        year: _year,
        company: _company,
        supplierType: _supplierType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = [
      for (var year = currentYear; year >= currentYear - 5; year--) year,
    ];
    final companies = {
      ...widget.companies.where((name) => name.trim().isNotEmpty),
      if (_company.trim().isNotEmpty) _company.trim(),
    }.toList()..sort();
    final selectedCompany = companies.contains(_company) ? _company : '';
    final selectedSupplierType =
        _purchaseSupplierTypeOptions.containsKey(_supplierType)
        ? _supplierType
        : 'all';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter Periode & Supplier',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                initialValue: _month,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bulan',
                  prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Semua Bulan')),
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(_purchaseMonthName(i)),
                    ),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _month = value ?? _month),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: years.contains(_year) ? _year : currentYear,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tahun',
                  prefixIcon: Icon(Icons.event_rounded, size: 18),
                ),
                items: [
                  for (final year in years)
                    DropdownMenuItem(value: year, child: Text('$year')),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _year = value ?? _year),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCompany,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Company',
                  prefixIcon: Icon(Icons.business_rounded, size: 18),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Semua Company'),
                  ),
                  for (final company in companies)
                    DropdownMenuItem(
                      value: company,
                      child: Text(company, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _company = value ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedSupplierType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Supplier',
                  prefixIcon: Icon(Icons.storefront_rounded, size: 18),
                ),
                items: [
                  for (final option in _purchaseSupplierTypeOptions.entries)
                    DropdownMenuItem(
                      value: option.key,
                      child: Text(option.value),
                    ),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(
                        () => _supplierType = value ?? _supplierType,
                      ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.loading ? null : _reset,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.loading ? null : _apply,
                      child: const Text('Terapkan Filter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _purchaseMonthName(int month) {
  const names = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  if (month < 1 || month > 12) return '-';
  return names[month - 1];
}

class _PurchaseDoctypePermissions {
  final bool canReadPurchaseOrder;
  final bool canCreatePurchaseOrder;
  final bool canReadPurchaseReceipt;
  final bool canCreatePurchaseReceipt;
  final bool canReadPurchaseInvoice;
  final bool canCreatePurchaseInvoice;
  final bool canReadMaterialRequest;
  final bool canCreateMaterialRequest;

  const _PurchaseDoctypePermissions({
    required this.canReadPurchaseOrder,
    required this.canCreatePurchaseOrder,
    required this.canReadPurchaseReceipt,
    required this.canCreatePurchaseReceipt,
    required this.canReadPurchaseInvoice,
    required this.canCreatePurchaseInvoice,
    required this.canReadMaterialRequest,
    required this.canCreateMaterialRequest,
  });

  factory _PurchaseDoctypePermissions.fullAccess() {
    return const _PurchaseDoctypePermissions(
      canReadPurchaseOrder: true,
      canCreatePurchaseOrder: true,
      canReadPurchaseReceipt: true,
      canCreatePurchaseReceipt: true,
      canReadPurchaseInvoice: true,
      canCreatePurchaseInvoice: true,
      canReadMaterialRequest: true,
      canCreateMaterialRequest: true,
    );
  }

  factory _PurchaseDoctypePermissions.legacyModuleAccess() {
    return _PurchaseDoctypePermissions.fullAccess();
  }

  bool get hasAnyAccess =>
      canReadPurchaseOrder ||
      canReadPurchaseReceipt ||
      canReadPurchaseInvoice ||
      canReadMaterialRequest;
}

class _PurchaseMenuEntry {
  final String key;
  final NavigationDestination destination;
  final Widget Function(ValueChanged<int> onMenuSelected) builder;
  final bool canCreate;

  const _PurchaseMenuEntry({
    required this.key,
    required this.destination,
    required this.builder,
    this.canCreate = false,
  });
}

class _NoPurchaseAccessScreen extends StatelessWidget {
  const _NoPurchaseAccessScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Tidak ada akses Purchase yang tersedia untuk user ini.',
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
