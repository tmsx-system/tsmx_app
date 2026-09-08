import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/dashboard/dashboard_state.dart';
import '../../state/logistics/logistics_overview_state.dart';
import '../../state/purchasing/purchase_order_state.dart';
import '../../state/selling/sales_order_state.dart';
import '../../state/todo/todo_state.dart';
import '../../state/warehouse/warehouse_stock_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard/dashboard_activity_carousel.dart';
import '../../widgets/dashboard/dashboard_module_launcher.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../profile/profile_screen.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _didInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dashboardState = context.read<DashboardState>();
      final showStockKpi =
          dashboardState.canUseStock || dashboardState.canUseWarehouse;
      Future.wait([
        if (dashboardState.canUseSales)
          context.read<SalesOrderState>().refreshSalesOrders(),
        if (dashboardState.canUsePurchase)
          context.read<PurchaseOrderState>().refreshPurchaseOrders(),
        if (showStockKpi)
          context.read<WarehouseStockState>().refreshInventory(),
        if (dashboardState.canUseLogistics)
          context.read<LogisticsOverviewState>().refreshDeliveryNotes(),
        if (dashboardState.canUseApprovals)
          context.read<TodoState>().fetchApprovalTodos(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<DashboardState>();

    final showStockKpi = appState.canUseStock || appState.canUseWarehouse;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await Future.wait([
          if (appState.canUseSales)
            context.read<SalesOrderState>().refreshSalesOrders(),
          if (appState.canUsePurchase)
            context.read<PurchaseOrderState>().refreshPurchaseOrders(),
          if (showStockKpi)
            context.read<WarehouseStockState>().refreshInventory(),
          if (appState.canUseLogistics)
            context.read<LogisticsOverviewState>().refreshDeliveryNotes(),
          if (appState.canUseApprovals)
            context.read<TodoState>().fetchApprovalTodos(forceRefresh: true),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 18, bottom: 110),
        child: TmsxResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardGreetingCard(appState: appState),
              const SizedBox(height: 18),
              const DashboardModuleLauncher(),
              const SizedBox(height: 18),
              const DashboardActivityCarousel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardGreetingCard extends StatelessWidget {
  final DashboardState appState;

  const _DashboardGreetingCard({required this.appState});

  @override
  Widget build(BuildContext context) {
    final rawName = appState.mobileBoot?.fullName.trim();
    final fallback = appState.currentUser?.split('@').first.trim() ?? 'User';
    final name = rawName?.isNotEmpty == true ? rawName! : fallback;
    final site = appState.selectedSiteName.trim().isNotEmpty
        ? appState.selectedSiteName.trim()
        : 'Workspace';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello,',
                  style: TextStyle(
                    color: AppColors.slate.withValues(alpha: 0.95),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      site,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Transform.rotate(
            angle: 0.18,
            child: Container(
              width: 88,
              height: 88,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF9FE9E6),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF14B8A6).withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: AppColors.white,
                size: 42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
