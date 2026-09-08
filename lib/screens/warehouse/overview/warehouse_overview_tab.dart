import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/inventory_item.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseOverviewTab extends StatelessWidget {
  final ValueChanged<int> onMenuSelected;

  const WarehouseOverviewTab({super.key, required this.onMenuSelected});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WarehouseStockState>();
    final lowStock = state.inventory
        .where((item) => item.status != StockStatus.inStock)
        .length;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          state.refreshWarehouses(),
          state.refreshInventory(),
          state.refreshStockEntries(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          _WarehouseHeroCard(
            warehouses: state.warehouses.length,
            lowStock: lowStock,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: WarehouseMetricTile(
                  label: 'Gudang',
                  value: '${state.warehouses.length}',
                  icon: Icons.warehouse_outlined,
                  color: warehousePurple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WarehouseMetricTile(
                  label: 'Peringatan stok',
                  value: '$lowStock',
                  icon: Icons.warning_amber_rounded,
                  color: lowStock > 0 ? warehouseOrange : warehouseGreen,
                ),
              ),
            ],
          ),
          warehouseSectionGap,
          const Text(
            'Menu Gudang',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: WarehouseActionGridCard(
                  title: 'Operasi',
                  subtitle: 'Transfer dan stock opname',
                  icon: Icons.swap_horiz_rounded,
                  color: warehouseOrange,
                  onTap: () => onMenuSelected(1),
                ),
              ),
              Expanded(
                child: WarehouseActionGridCard(
                  title: 'Stok',
                  subtitle: 'Realtime, valuasi, aging',
                  icon: Icons.inventory_2_rounded,
                  color: warehouseGreen,
                  onTap: () => onMenuSelected(2),
                ),
              ),
              Expanded(
                child: WarehouseActionGridCard(
                  title: 'QC',
                  subtitle: 'Inspection dan approval',
                  icon: Icons.fact_check_rounded,
                  color: warehouseBlue,
                  onTap: () => onMenuSelected(3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarehouseHeroCard extends StatelessWidget {
  final int warehouses;
  final int lowStock;

  const _WarehouseHeroCard({required this.warehouses, required this.lowStock});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: warehouseGreen,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: warehouseGreen.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: const Icon(
              Icons.warehouse_rounded,
              color: AppColors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Warehouse',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lowStock > 0
                      ? '$lowStock item perlu perhatian stok'
                      : 'Stok dan aktivitas gudang siap dipantau',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$warehouses',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Text(
                  'Gudang',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
