import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sales_order.dart';
import '../services/native_notification_service.dart';
import '../state/auth/auth_state.dart';
import '../state/dashboard/dashboard_state.dart';
import '../state/selling/sales_order_state.dart';
import '../state/todo/todo_state.dart';
import '../theme/app_colors.dart';
import '../utils/erp_doc_utils.dart';
import '../utils/erp_format.dart';
import '../widgets/responsive/responsive_layout.dart';
import '../config/mobile_role_registry.dart';
import 'auth/login_screen.dart';
import 'profile/profile_screen.dart';
import 'shared/module_screen_registry.dart';

import 'tabs/dashboard_tab.dart';
import 'purchase/purchase_order/create_purchase_order_screen.dart';
import 'purchase/purchase_invoice/create_purchase_invoice_screen.dart';
import 'purchase/purchase_receipt/create_purchase_receipt_screen.dart';
import 'purchase/material_request/create_material_request_screen.dart';
import 'stock/stock_entry/create_stock_entry_screen.dart';
import 'sales/sales_order/create_sales_order_screen.dart';
import 'spg/daily_activity/create_spg_daily_activity_screen.dart';
import 'spg/daily_report/create_spg_daily_report_screen.dart';
import 'todo/todo_list.dart';
import 'visits/attendance_tab.dart';

class AppMainScreen extends StatefulWidget {
  const AppMainScreen({super.key});

  @override
  State<AppMainScreen> createState() => _AppMainScreenState();
}

class _AppMainScreenState extends State<AppMainScreen> {
  static const _profileTabKey = 'profile';

  int _currentIndex = 0;
  bool _pendingOpenApprovalTodo = false;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notificationTapSub = NativeNotificationService.instance.notificationTaps
          .listen(_handleNotificationTap);
      NativeNotificationService.instance.consumeInitialTapPayload().then((
        payload,
      ) {
        if (payload != null) _handleNotificationTap(payload);
      });
    });
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    super.dispose();
  }

  int _totalTodoCount(TodoState state) => state.approvalTodoCount;

  List<ModuleLaunchEntry> _workspaceEntries(DashboardState state) {
    return ModuleScreenRegistry.launchEntriesFor(
      state.mobileAccess.enabledModules,
    );
  }

  List<_MainTabItem> _tabs(DashboardState state, TodoState todoState) {
    final workspaceEntries = _workspaceEntries(state);
    final singleWorkspace =
        workspaceEntries.length == 1 && !state.canUseApprovals;
    final tabs = <_MainTabItem>[
      _MainTabItem(
        keyName: MobileModule.dashboard,
        child: singleWorkspace
            ? workspaceEntries.single.screen
            : const DashboardTab(),
        destination: NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: _moduleLabel(state, MobileModule.dashboard, 'Beranda'),
        ),
        navIcon: Icons.home_outlined,
        selectedNavIcon: Icons.home_rounded,
      ),
    ];

    if (state.canUseApprovals) {
      final todoCount = _totalTodoCount(todoState);
      tabs.add(
        _MainTabItem(
          keyName: MobileModule.approvals,
          child: const SalesOrderApprovalScreen(
            embedded: true,
            title: 'Approval Dokumen',
          ),
          destination: NavigationDestination(
            icon: _todoIcon(Icons.checklist_outlined, todoCount),
            selectedIcon: _todoIcon(Icons.checklist_rounded, todoCount),
            label: _moduleLabel(state, MobileModule.approvals, 'Todo'),
          ),
          navIcon: Icons.checklist_outlined,
          selectedNavIcon: Icons.checklist_rounded,
          badgeCount: todoCount,
        ),
      );
    }

    tabs.add(
      _MainTabItem(
        keyName: _profileTabKey,
        child: const ProfileScreen(showBackButton: false),
        destination: const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profil',
        ),
        navIcon: Icons.person_outline_rounded,
        selectedNavIcon: Icons.person_rounded,
      ),
    );

    return tabs;
  }

  String _moduleLabel(DashboardState state, String module, String fallback) {
    final bootMenus = (state.mobileBoot?.menus ?? const [])
        .map((menu) => (module: menu.module, label: menu.label))
        .toList();
    return MobileRoleRegistry.moduleLabel(
      module,
      bootMenus: bootMenus,
      fallback: fallback,
    );
  }

  void _changeTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _handleNotificationTap(Map<String, dynamic> payload) {
    if (!mounted) return;
    if (payload['target']?.toString() != 'approval_todo') return;
    _pendingOpenApprovalTodo = true;
    _openApprovalTodoTabIfReady();
  }

  void _openApprovalTodoTabIfReady() {
    if (!mounted || !_pendingOpenApprovalTodo) return;
    final dashboardState = context.read<DashboardState>();
    final todoState = context.read<TodoState>();
    if (!dashboardState.canUseApprovals) return;
    final tabs = _tabs(dashboardState, todoState);
    final todoIndex = tabs.indexWhere(
      (tab) => tab.keyName == MobileModule.approvals,
    );
    if (todoIndex < 0) return;
    _pendingOpenApprovalTodo = false;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _currentIndex = todoIndex);
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final dashboardState = context.watch<DashboardState>();
    final todoState = context.watch<TodoState>();

    if (!authState.isAuthenticated) {
      _redirectToLogin();

      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final tabs = _tabs(dashboardState, todoState);
    final selectedIndex = _currentIndex.clamp(0, tabs.length - 1);
    final workspaceEntries = _workspaceEntries(dashboardState);
    final singleWorkspace =
        selectedIndex == 0 &&
        workspaceEntries.length == 1 &&
        !dashboardState.canUseApprovals;
    if (_pendingOpenApprovalTodo &&
        tabs.any((tab) => tab.keyName == MobileModule.approvals)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openApprovalTodoTabIfReady();
      });
    }
    if (selectedIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = selectedIndex);
      });
    }
    final selectedTab = tabs[selectedIndex];
    if (singleWorkspace) {
      return KeyedSubtree(
        key: ValueKey(selectedTab.keyName),
        child: selectedTab.child,
      );
    }
    final showShellAppBar =
        selectedTab.keyName != _profileTabKey && !singleWorkspace;
    final showCreateFab =
        selectedTab.keyName == MobileModule.dashboard && !singleWorkspace;

    return PopScope(
      canPop: selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectedIndex != 0) {
          _changeTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: showShellAppBar
            ? AppBar(
                toolbarHeight: 76,
                backgroundColor: AppColors.white,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                centerTitle: false,
                titleSpacing: 18,
                title: _TmsxHeaderTitle(state: dashboardState),
                actions: [
                  if (dashboardState.canUseApprovals)
                    _TopBarActionButton(
                      tooltip: _totalTodoCount(todoState) > 0
                          ? '${_totalTodoCount(todoState)} approval menunggu'
                          : 'Tidak ada approval menunggu',
                      icon: Icons.assignment_turned_in_outlined,
                      count: _totalTodoCount(todoState),
                      onTap: () {
                        final todoIndex = tabs.indexWhere(
                          (tab) => tab.keyName == MobileModule.approvals,
                        );
                        if (todoIndex >= 0) _changeTab(todoIndex);
                      },
                    ),
                  const SizedBox(width: 18),
                ],
              )
            : null,
        body: Stack(
          children: [
            for (var index = 0; index < tabs.length; index++)
              Positioned.fill(
                child: _LazyMainTabPane(
                  active: index == selectedIndex,
                  child: KeyedSubtree(
                    key: ValueKey(tabs[index].keyName),
                    child: TmsxResponsiveBody(child: tabs[index].child),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: showCreateFab
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CreateButton(
                  onTap: () => _showQuickCreateSheet(context, authState),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _TmsxBottomNav(
          tabs: tabs,
          selectedIndex: selectedIndex,
          onSelected: _changeTab,
        ),
      ),
    );
  }

  Widget _todoIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Badge.count(
      count: count,
      backgroundColor: AppColors.danger,
      textColor: AppColors.white,
      child: Icon(icon),
    );
  }

  Future<void> _showQuickCreateSheet(
    BuildContext context,
    AuthState authState,
  ) async {
    final canCreateSalesOrder = await authState.canCreateDoctype('Sales Order');
    final canCreateDeliveryNote = await authState.canCreateDoctype(
      'Delivery Note',
    );
    final canCreateSalesInvoice = await authState.canCreateDoctype(
      'Sales Invoice',
    );
    final canCreateSalesVisit = await authState.canCreateDoctype('Sales Visit');
    final canCreateSpgVisit = await authState.canCreateDoctype('SPG Visit');
    final canCreateSpgDailyActivity = await authState.canCreateDoctype(
      'SPG Daily Activity',
    );
    final canCreateSpgDailyReport = await authState.canCreateDoctype(
      'SPG Daily Report',
    );
    final canCreatePurchaseOrder = await authState.canCreateDoctype(
      'Purchase Order',
    );
    final canCreatePurchaseReceipt = await authState.canCreateDoctype(
      'Purchase Receipt',
    );
    final canCreatePurchaseInvoice = await authState.canCreateDoctype(
      'Purchase Invoice',
    );
    final canCreateMaterialRequest = await authState.canCreateDoctype(
      'Material Request',
    );
    final canCreateStockEntry = await authState.canCreateDoctype('Stock Entry');

    if (!context.mounted) return;

    final salesActions = <_QuickCreateAction>[
      if (canCreateSalesOrder)
        _QuickCreateAction(
          title: 'Sales Order',
          subtitle: 'Order customer baru',
          icon: Icons.point_of_sale_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateSalesOrderScreen()),
          ),
        ),
      if (canCreateSalesVisit)
        _QuickCreateAction(
          title: 'Check-in Sales',
          subtitle: 'Absensi customer sales',
          icon: Icons.add_location_alt_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AttendanceCheckInScreen()),
          ),
        ),
      if (canCreateDeliveryNote)
        _QuickCreateAction(
          title: 'Delivery Note',
          subtitle: 'Dari Sales Order submitted',
          icon: Icons.local_shipping_outlined,
          onTap: () => _createDeliveryNoteFromSalesOrder(context),
        ),
      if (canCreateSalesInvoice)
        _QuickCreateAction(
          title: 'Sales Invoice',
          subtitle: 'Tagihan dari Sales Order',
          icon: Icons.receipt_long_outlined,
          onTap: () => _createSalesInvoiceFromSalesOrder(context),
        ),
    ];

    final canUseSpgCreateFallback =
        authState.canUseSpg &&
        !canCreateSpgVisit &&
        !canCreateSpgDailyActivity &&
        !canCreateSpgDailyReport;

    final spgActions = <_QuickCreateAction>[
      if (canCreateSpgVisit || canUseSpgCreateFallback)
        _QuickCreateAction(
          title: 'Check-in SPG',
          subtitle: 'Absensi customer sesuai schedule',
          icon: Icons.add_location_alt_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AttendanceCheckInScreen(spgMode: true),
            ),
          ),
        ),
      if (canCreateSpgDailyActivity || canUseSpgCreateFallback)
        _QuickCreateAction(
          title: 'Report Foto',
          subtitle: 'Upload foto aktivitas harian',
          icon: Icons.photo_camera_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateSpgDailyActivityScreen(),
            ),
          ),
        ),
      if (canCreateSpgDailyReport || canUseSpgCreateFallback)
        _QuickCreateAction(
          title: 'Report Selling',
          subtitle: 'Input stok awal, akhir, dan sell out',
          icon: Icons.bar_chart_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateSpgDailyReportScreen(),
            ),
          ),
        ),
    ];

    final purchaseActions = <_QuickCreateAction>[
      if (canCreatePurchaseOrder)
        _QuickCreateAction(
          title: 'Purchase Order',
          subtitle: 'PO supplier',
          icon: Icons.add_shopping_cart_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreatePurchaseOrderScreen(),
            ),
          ),
        ),
      if (canCreatePurchaseReceipt)
        _QuickCreateAction(
          title: 'Purchase Receipt',
          subtitle: 'Terima barang',
          icon: Icons.move_to_inbox_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreatePurchaseReceiptScreen(),
            ),
          ),
        ),
      if (canCreatePurchaseInvoice)
        _QuickCreateAction(
          title: 'Purchase Invoice',
          subtitle: 'Invoice supplier',
          icon: Icons.receipt_long_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreatePurchaseInvoiceScreen(),
            ),
          ),
        ),
      if (canCreateMaterialRequest)
        _QuickCreateAction(
          title: 'Material Request',
          subtitle: 'Kebutuhan barang',
          icon: Icons.assignment_add,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateMaterialRequestScreen(),
            ),
          ),
        ),
    ];

    final stockActions = <_QuickCreateAction>[
      if (canCreateStockEntry)
        _QuickCreateAction(
          title: 'Stock Entry',
          subtitle: 'Transfer, receipt, issue',
          icon: Icons.inventory_2_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateStockEntryScreen()),
          ),
        ),
    ];

    final groups = <_QuickCreateGroup>[
      if (authState.canUseSales && salesActions.isNotEmpty)
        _QuickCreateGroup(
          title: 'Sales',
          icon: Icons.point_of_sale_rounded,
          actions: salesActions,
        ),
      if (authState.canUseSpg && spgActions.isNotEmpty)
        _QuickCreateGroup(
          title: 'SPG',
          icon: Icons.storefront_rounded,
          actions: spgActions,
        ),
      if (authState.canUsePurchase && purchaseActions.isNotEmpty)
        _QuickCreateGroup(
          title: 'Purchase',
          icon: Icons.shopping_bag_rounded,
          actions: purchaseActions,
        ),
      if (authState.canUseStock && stockActions.isNotEmpty)
        _QuickCreateGroup(
          title: 'Stock',
          icon: Icons.inventory_2_rounded,
          actions: stockActions,
        ),
    ];
    final actionsCount = groups.fold<int>(
      0,
      (total, group) => total + group.actions.length,
    );

    if (actionsCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada aksi create untuk role ini.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Create Document',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final group in groups)
                          _QuickCreateSection(
                            group: group,
                            onActionTap: (action) async {
                              Navigator.pop(sheetContext);
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              if (!context.mounted) return;
                              await action.onTap();
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createDeliveryNoteFromSalesOrder(BuildContext context) async {
    final selection = await _pickSalesOrderFor(
      context,
      doctype: 'Delivery Note',
      title: 'Create Delivery Note',
      emptyMessage: 'Tidak ada Sales Order submitted yang masih perlu dikirim.',
      canUse: (order) =>
          isDocSubmitted(order.docStatus) && order.perDelivered < 100,
    );
    if (selection == null || !context.mounted) return;

    await _runSalesOrderCreateAction(
      context,
      action: () =>
          context.read<SalesOrderState>().createDeliveryNoteFromSalesOrder(
            selection.order.id,
            namingSeries: selection.namingSeries,
          ),
      successMessage:
          'Delivery Note berhasil dibuat dari ${selection.order.id}',
      failurePrefix: 'Gagal membuat Delivery Note',
    );
  }

  Future<void> _createSalesInvoiceFromSalesOrder(BuildContext context) async {
    final selection = await _pickSalesOrderFor(
      context,
      doctype: 'Sales Invoice',
      title: 'Create Sales Invoice',
      emptyMessage: 'Tidak ada Sales Order submitted yang masih perlu ditagih.',
      canUse: (order) =>
          isDocSubmitted(order.docStatus) && order.perBilled < 100,
    );
    if (selection == null || !context.mounted) return;

    await _runSalesOrderCreateAction(
      context,
      action: () =>
          context.read<SalesOrderState>().createSalesInvoiceFromSalesOrder(
            selection.order.id,
            namingSeries: selection.namingSeries,
          ),
      successMessage:
          'Sales Invoice berhasil dibuat dari ${selection.order.id}',
      failurePrefix: 'Gagal membuat Sales Invoice',
    );
  }

  Future<_SalesOrderDraftSelection?> _pickSalesOrderFor(
    BuildContext context, {
    required String doctype,
    required String title,
    required String emptyMessage,
    required bool Function(SalesOrder order) canUse,
  }) async {
    final salesOrderState = context.read<SalesOrderState>();
    if (salesOrderState.salesOrders.isEmpty) {
      await salesOrderState.refreshSalesOrders();
      if (!context.mounted) return null;
    }

    final candidates = salesOrderState.salesOrders.where(canUse).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emptyMessage), backgroundColor: Colors.orange),
      );
      return null;
    }

    List<String> namingSeries;
    try {
      namingSeries = await salesOrderState.fetchNamingSeries(doctype);
    } catch (error) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat naming series $doctype: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return null;
    }
    if (namingSeries.isEmpty || !context.mounted) return null;

    return showModalBottomSheet<_SalesOrderDraftSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        var query = '';
        SalesOrder? selectedOrder;
        String selectedSeries = namingSeries.first;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final filtered = normalized.isEmpty
                ? candidates.take(60).toList()
                : candidates.where((order) {
                    return order.id.toLowerCase().contains(normalized) ||
                        order.customer.toLowerCase().contains(normalized);
                  }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      autofocus: true,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        labelText: 'Search Sales Order / customer',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSeries,
                      decoration: const InputDecoration(
                        labelText: 'Naming Series',
                      ),
                      items: namingSeries
                          .map(
                            (series) => DropdownMenuItem(
                              value: series,
                              child: Text(series),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selectedSeries = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.of(sheetContext).size.height * 0.48,
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'Sales Order tidak ditemukan',
                                style: TextStyle(color: AppColors.slate),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final order = filtered[index];
                                return ListTile(
                                  selected: selectedOrder?.id == order.id,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    order.id,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${order.customer} - ${order.date}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    'Rp ${formatErpCurrency(order.value)}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () => setSheetState(
                                    () => selectedOrder = order,
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: selectedOrder == null
                          ? null
                          : () => Navigator.pop(
                              sheetContext,
                              _SalesOrderDraftSelection(
                                order: selectedOrder!,
                                namingSeries: selectedSeries,
                              ),
                            ),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Buat Draft'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _runSalesOrderCreateAction(
    BuildContext context, {
    required Future<dynamic> Function() action,
    required String successMessage,
    required String failurePrefix,
  }) async {
    try {
      await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$failurePrefix: $err'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

class _SalesOrderDraftSelection {
  final SalesOrder order;
  final String namingSeries;

  const _SalesOrderDraftSelection({
    required this.order,
    required this.namingSeries,
  });
}

class _QuickCreateAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function() onTap;

  const _QuickCreateAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

class _QuickCreateGroup {
  final String title;
  final IconData icon;
  final List<_QuickCreateAction> actions;

  const _QuickCreateGroup({
    required this.title,
    required this.icon,
    required this.actions,
  });
}

class _QuickCreateSection extends StatelessWidget {
  final _QuickCreateGroup group;
  final ValueChanged<_QuickCreateAction> onActionTap;

  const _QuickCreateSection({required this.group, required this.onActionTap});

  @override
  Widget build(BuildContext context) {
    if (group.actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Row(
              children: [
                Icon(group.icon, color: AppColors.primary, size: 18),
                const SizedBox(width: 7),
                Text(
                  group.title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var index = 0; index < group.actions.length; index++) ...[
                  _QuickCreateTile(
                    action: group.actions[index],
                    onTap: () => onActionTap(group.actions[index]),
                  ),
                  if (index < group.actions.length - 1)
                    const Divider(height: 1, color: AppColors.border),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCreateTile extends StatelessWidget {
  final _QuickCreateAction action;
  final VoidCallback onTap;

  const _QuickCreateTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(action.icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
          ],
        ),
      ),
    ),
  );
}

class _LazyMainTabPane extends StatefulWidget {
  final bool active;
  final Widget child;

  const _LazyMainTabPane({required this.active, required this.child});

  @override
  State<_LazyMainTabPane> createState() => _LazyMainTabPaneState();
}

class _LazyMainTabPaneState extends State<_LazyMainTabPane> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loaded = widget.active;
  }

  @override
  void didUpdateWidget(covariant _LazyMainTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_loaded) {
      _loaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(enabled: widget.active, child: widget.child),
    );
  }
}

class _MainTabItem {
  final String keyName;
  final Widget child;
  final NavigationDestination destination;
  final IconData navIcon;
  final IconData selectedNavIcon;
  final int badgeCount;

  const _MainTabItem({
    required this.keyName,
    required this.child,
    required this.destination,
    required this.navIcon,
    required this.selectedNavIcon,
    this.badgeCount = 0,
  });
}

class _TmsxHeaderTitle extends StatelessWidget {
  final DashboardState state;

  const _TmsxHeaderTitle({required this.state});

  @override
  Widget build(BuildContext context) {
    final tenant = state.selectedSiteName.trim();
    final user = state.currentUser ?? 'Operator';
    final subtitle = tenant.isNotEmpty ? tenant : user;

    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.appDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _TopBarActionButton({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              if (count > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TmsxBottomNav extends StatelessWidget {
  final List<_MainTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _TmsxBottomNav({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(18, 4, 18, bottomPadding > 0 ? 8 : 14),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.white),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.11),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < tabs.length; index++)
                      Expanded(
                        child: _TmsxBottomNavItem(
                          tab: tabs[index],
                          selected: index == selectedIndex,
                          compact: tabs.length >= 4,
                          onTap: () => onSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 11,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_rounded,
              color: AppColors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _TmsxBottomNavItem extends StatelessWidget {
  final _MainTabItem tab;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _TmsxBottomNavItem({
    required this.tab,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = tab.destination.label;
    final color = selected ? AppColors.primary : AppColors.slate;
    final icon = selected ? tab.selectedNavIcon : tab.navIcon;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
          padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 7),
          decoration: const BoxDecoration(color: Colors.transparent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 34 : 30,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.softGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: _BottomNavIcon(
                  icon: icon,
                  color: color,
                  count: tab.badgeCount,
                  size: selected ? 20 : 21,
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 9.5 : 10.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 4,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final double size;

  const _BottomNavIcon({
    required this.icon,
    required this.color,
    required this.count,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: color, size: size);
    if (count <= 0) return iconWidget;
    return Badge.count(
      count: count,
      backgroundColor: AppColors.danger,
      textColor: AppColors.white,
      smallSize: 7,
      textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
      child: iconWidget,
    );
  }
}
