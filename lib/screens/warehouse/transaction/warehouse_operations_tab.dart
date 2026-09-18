import 'package:flutter/material.dart';

import '../shared/warehouse_widgets.dart';
import '../stock/stock_entry/stock_entry_kind.dart';
import '../stock/stock_entry/stock_entry_panel.dart';
import 'warehouse_stock_opname_screen.dart';

class WarehouseOperationsTab extends StatelessWidget {
  const WarehouseOperationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _WarehouseTransactionAction(
        onTap: () => _openStockEntry(context),
        icon: Icons.swap_horiz_rounded,
        title: 'Stock Entry',
        subtitle: 'Transfer, receipt, issue, dan tipe ERPNext lain',
        color: warehouseOrange,
      ),
      _WarehouseTransactionAction(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WarehouseStockOpnameScreen()),
        ),
        icon: Icons.inventory_outlined,
        title: 'Stock Opname',
        subtitle: 'Stock Reconciliation',
        color: warehousePurple,
      ),
    ];

    return ListView(
      padding: warehousePagePaddingOf(context),
      children: [
        const WarehouseSectionHeader(
          title: 'Transaksi Gudang',
          subtitle: 'Mendukung transaksi Gudang',
          icon: Icons.store_outlined,
        ),
        warehouseSectionGap,
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.86,
          children: actions
              .map(
                (action) => WarehouseActionGridCard(
                  onTap: action.onTap,
                  icon: action.icon,
                  title: action.title,
                  subtitle: action.subtitle,
                  color: action.color,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Future<void> _openStockEntry(BuildContext context) async {
    final kind = await showStockEntryTypePicker(context);
    if (kind == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockEntryPanel(kind: kind),
      ),
    );
  }
}

class _WarehouseTransactionAction {
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _WarehouseTransactionAction({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
