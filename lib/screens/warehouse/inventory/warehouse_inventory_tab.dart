import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/warehouse/warehouse_aging_state.dart';
import '../../../state/warehouse/warehouse_dead_stock_state.dart';
import '../../../state/warehouse/warehouse_valuation_state.dart';
import '../../../theme/app_colors.dart';
import '../../tabs/stock_tab.dart';
import 'warehouse_dead_stock_view.dart';
import 'warehouse_fast_slow_moving_view.dart';
import 'warehouse_inventory_valuation_view.dart';
import 'warehouse_stock_aging_view.dart';

class WarehouseInventoryTab extends StatefulWidget {
  const WarehouseInventoryTab({super.key});

  @override
  State<WarehouseInventoryTab> createState() => _WarehouseInventoryTabState();
}

class _WarehouseInventoryTabState extends State<WarehouseInventoryTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureActiveTabLoaded();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    _ensureActiveTabLoaded();
  }

  void _ensureActiveTabLoaded() {
    switch (_tabController.index) {
      case 1:
        final state = context.read<WarehouseValuationState>();
        if (state.inventory.isEmpty) {
          state.refreshInventory(forceRefresh: false);
        }
        break;
      case 2:
        final state = context.read<WarehouseAgingState>();
        if (!state.hasLoaded) {
          state.fetchStockAging();
        }
        break;
      case 3:
        final state = context.read<WarehouseDeadStockState>();
        if (!state.hasVelocityLoaded) {
          state.fetchStockMovementVelocity();
        }
        break;
      case 4:
        final state = context.read<WarehouseDeadStockState>();
        if (!state.hasDeadStockLoaded) {
          state.fetchDeadStock();
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppColors.white,
                unselectedLabelColor: AppColors.slate,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                tabs: const [
                  Tab(text: 'Stok'),
                  Tab(text: 'Valuasi'),
                  Tab(text: 'Aging'),
                  Tab(text: 'Fast / Slow'),
                  Tab(text: 'Dead Stock'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                StockTab(),
                WarehouseInventoryValuationView(),
                WarehouseStockAgingView(),
                WarehouseFastSlowMovingView(),
                WarehouseDeadStockView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
