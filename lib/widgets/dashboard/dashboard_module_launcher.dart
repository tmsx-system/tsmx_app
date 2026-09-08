import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mobile_role_registry.dart';
import '../../models/delivery_note.dart';
import '../../models/inventory_item.dart';
import '../../models/mobile_boot.dart';
import '../../models/purchase_order.dart';
import '../../models/sales_order.dart';
import '../../screens/shared/module_screen_registry.dart';
import '../../state/dashboard/dashboard_state.dart';
import '../../state/logistics/logistics_overview_state.dart';
import '../../state/purchasing/purchase_order_state.dart';
import '../../state/selling/sales_order_state.dart';
import '../../state/todo/todo_state.dart';
import '../../state/warehouse/warehouse_stock_state.dart';
import '../../theme/app_colors.dart';

class DashboardModuleLauncher extends StatefulWidget {
  const DashboardModuleLauncher({super.key});

  @override
  State<DashboardModuleLauncher> createState() =>
      _DashboardModuleLauncherState();
}

class _DashboardModuleLauncherState extends State<DashboardModuleLauncher> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<DashboardState>();
    final salesState = context.watch<SalesOrderState>();
    final purchaseState = context.watch<PurchaseOrderState>();
    final stockState = context.watch<WarehouseStockState>();
    final logisticsState = context.watch<LogisticsOverviewState>();
    final todoState = context.watch<TodoState>();
    final groups = _buildGroups(
      appState,
      salesState: salesState,
      purchaseState: purchaseState,
      stockState: stockState,
      logisticsState: logisticsState,
      todoState: todoState,
    );
    if (groups.isEmpty) return const SizedBox.shrink();
    final entries = [for (final group in groups) ...group.entries];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 360 ? 4 : 3;
        const rowsPerPage = 3;
        const tileHeight = 88.0;
        const rowGap = 14.0;
        final pageSize = crossAxisCount * rowsPerPage;
        final pages = _chunkEntries(entries, pageSize);
        final safePage = _page.clamp(0, pages.length - 1);
        if (safePage != _page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _page = safePage);
          });
        }
        final gridHeight =
            rowsPerPage * tileHeight + (rowsPerPage - 1) * rowGap;

        return Column(
          children: [
            SizedBox(
              height: gridHeight,
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, pageIndex) {
                  final pageEntries = pages[pageIndex];
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pageEntries.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: rowGap,
                      crossAxisSpacing: 10,
                      mainAxisExtent: tileHeight,
                    ),
                    itemBuilder: (context, index) {
                      return _ModuleEntryTile(entry: pageEntries[index]);
                    },
                  );
                },
              ),
            ),
            if (pages.length > 1) ...[
              const SizedBox(height: 10),
              _ModulePageDots(count: pages.length, activeIndex: safePage),
            ],
          ],
        );
      },
    );
  }

  List<List<_ModuleEntry>> _chunkEntries(
    List<_ModuleEntry> entries,
    int pageSize,
  ) {
    final pages = <List<_ModuleEntry>>[];
    for (var index = 0; index < entries.length; index += pageSize) {
      final end = (index + pageSize).clamp(0, entries.length);
      pages.add(entries.sublist(index, end));
    }
    return pages;
  }

  List<_ModuleGroup> _buildGroups(
    DashboardState appState, {
    required SalesOrderState salesState,
    required PurchaseOrderState purchaseState,
    required WarehouseStockState stockState,
    required LogisticsOverviewState logisticsState,
    required TodoState todoState,
  }) {
    final enabled = appState.mobileAccess.enabledModules;
    final launchEntries = ModuleScreenRegistry.launchEntriesFor(enabled);
    if (launchEntries.isEmpty) return const [];

    final bootMenus = _bootMenuItems(appState.mobileBoot);
    final bootMenuOrder = _bootMenuOrder(appState.mobileBoot);
    final grouped = <String, List<_ModuleEntry>>{};

    for (final entry in launchEntries) {
      grouped
          .putIfAbsent(entry.meta.groupKey, () => [])
          .add(
            _ModuleEntry(
              entry: entry,
              screen: _screenForEntry(appState, entry),
              order: bootMenuOrder[entry.moduleKey] ?? entry.meta.menuOrder,
              title: entry.routeKey == entry.moduleKey
                  ? MobileRoleRegistry.moduleLabel(
                      entry.moduleKey,
                      bootMenus: bootMenus,
                      fallback: entry.title,
                    )
                  : entry.title,
              subtitle: entry.subtitle,
              badgeLabel: _badgeForEntry(
                appState,
                entry,
                salesState: salesState,
                purchaseState: purchaseState,
                stockState: stockState,
                logisticsState: logisticsState,
                todoState: todoState,
              ),
              badgeColor: _badgeColorForEntry(todoState, entry),
            ),
          );
    }

    final groups = <_ModuleGroup>[];
    for (final groupMeta in MobileRoleRegistry.sortedGroups()) {
      final entries = grouped[groupMeta.key];
      if (entries == null || entries.isEmpty) continue;
      entries.sort((a, b) => a.order.compareTo(b.order));
      groups.add(_ModuleGroup(entries: entries));
    }

    return groups;
  }

  List<({String module, String label})> _bootMenuItems(MobileBoot? boot) {
    return (boot?.menus ?? const [])
        .map((menu) => (module: menu.module, label: menu.label))
        .toList();
  }

  Map<String, int> _bootMenuOrder(MobileBoot? boot) {
    final order = <String, int>{};
    for (final menu in boot?.menus ?? const <MobileBootMenuItem>[]) {
      if (menu.module.trim().isEmpty || menu.order <= 0) continue;
      order[menu.module] = menu.order;
    }
    return order;
  }

  String _badgeForEntry(
    DashboardState appState,
    ModuleLaunchEntry entry, {
    required SalesOrderState salesState,
    required PurchaseOrderState purchaseState,
    required WarehouseStockState stockState,
    required LogisticsOverviewState logisticsState,
    required TodoState todoState,
  }) {
    switch (entry.routeKey) {
      case MobileModule.sales:
        final openSales = salesState.salesOrders.where((order) {
          return order.statusKey != SalesOrderStatusKey.completed &&
              order.statusKey != SalesOrderStatusKey.cancelled &&
              order.statusKey != SalesOrderStatusKey.closed;
        }).length;
        return _countLabel(openSales, 'open');
      case MobileModule.purchase:
        if (todoState.purchaseApprovalTodoCount > 0) {
          return '${todoState.purchaseApprovalTodoCount} approval';
        }
        final openPurchases = purchaseState.purchaseOrders.where((order) {
          return order.statusKey != PurchaseOrderStatusKey.completed &&
              order.statusKey != PurchaseOrderStatusKey.cancelled &&
              order.statusKey != PurchaseOrderStatusKey.closed;
        }).length;
        return _countLabel(openPurchases, 'open');
      case MobileModule.stock:
        final alertCount = stockState.inventory
            .where(
              (item) =>
                  item.status == StockStatus.lowStock ||
                  item.status == StockStatus.urgent,
            )
            .length;
        return _countLabel(alertCount, 'alert');
      case MobileModule.warehouse:
        return _countLabel(stockState.warehouses.length, 'gudang');
      case MobileModule.logistics:
      case 'logistics.delivery':
        final outstanding = logisticsState.deliveryNotes.where((doc) {
          return doc.statusKey != DeliveryNoteStatusKey.completed &&
              doc.statusKey != DeliveryNoteStatusKey.cancelled &&
              doc.statusKey != DeliveryNoteStatusKey.closed;
        }).length;
        return _countLabel(outstanding, 'jalan');
      default:
        return '';
    }
  }

  Color _badgeColorForEntry(TodoState todoState, ModuleLaunchEntry entry) {
    if (entry.moduleKey == MobileModule.purchase &&
        todoState.purchaseApprovalTodoCount > 0) {
      return AppColors.danger;
    }
    if (entry.moduleKey == MobileModule.stock) return AppColors.warning;
    if (entry.moduleKey == MobileModule.logistics) return AppColors.warning;
    return AppColors.primary;
  }

  String _countLabel(int count, String suffix) {
    if (count <= 0) return '';
    return '$count $suffix';
  }

  Widget _screenForEntry(DashboardState appState, ModuleLaunchEntry entry) {
    return entry.screen;
  }
}

class _ModulePageDots extends StatelessWidget {
  const _ModulePageDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(count, (index) {
      final active = index == activeIndex;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: active ? 18 : 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }),
  );
}

class _ModuleGroup {
  final List<_ModuleEntry> entries;

  const _ModuleGroup({required this.entries});
}

class _ModuleEntry {
  final ModuleLaunchEntry entry;
  final Widget screen;
  final int order;
  final String title;
  final String subtitle;
  final String badgeLabel;
  final Color badgeColor;

  const _ModuleEntry({
    required this.entry,
    required this.screen,
    required this.order,
    required this.title,
    required this.subtitle,
    this.badgeLabel = '',
    this.badgeColor = AppColors.primary,
  });
}

class _ModuleEntryTile extends StatelessWidget {
  final _ModuleEntry entry;

  const _ModuleEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = _moduleColors(entry.entry.routeKey);
    return Tooltip(
      message: entry.subtitle,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => entry.screen));
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: colors.background.withValues(alpha: 0.36),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  entry.entry.meta.icon,
                  color: colors.foreground,
                  size: 25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({Color background, Color foreground}) _moduleColors(String routeKey) {
  switch (routeKey) {
    case MobileModule.sales:
      return (background: const Color(0xFF16A34A), foreground: Colors.white);
    case MobileModule.spg:
      return (background: const Color(0xFF059669), foreground: Colors.white);
    case MobileModule.collection:
      return (background: const Color(0xFF0F766E), foreground: Colors.white);
    case MobileModule.purchase:
      return (background: const Color(0xFF22C55E), foreground: Colors.white);
    case MobileModule.stock:
      return (background: const Color(0xFF0284C7), foreground: Colors.white);
    case MobileModule.warehouse:
      return (background: const Color(0xFF4F46E5), foreground: Colors.white);
    case MobileModule.qualityControl:
      return (background: const Color(0xFF0EA5E9), foreground: Colors.white);
    case MobileModule.logistics:
      return (background: const Color(0xFFEA580C), foreground: Colors.white);
    case 'logistics.tracking':
      return (background: const Color(0xFFF59E0B), foreground: Colors.white);
    case 'logistics.delivery':
      return (background: const Color(0xFF16A34A), foreground: Colors.white);
    case MobileModule.finance:
      return (background: const Color(0xFF2563EB), foreground: Colors.white);
    case MobileModule.accounting:
      return (background: const Color(0xFF0891B2), foreground: Colors.white);
    case MobileModule.plantation:
      return (background: const Color(0xFF22C55E), foreground: Colors.white);
    default:
      return (background: AppColors.primary, foreground: Colors.white);
  }
}
