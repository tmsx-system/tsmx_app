import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/warehouse_widgets.dart';
import 'stock/stock_entry/stock_entry_kind.dart';
import 'stock/stock_entry/stock_entry_panel.dart';
import 'stock/stock_reconciliation/stock_reconciliation_panel.dart';

class WarehouseOperationsTab extends StatefulWidget {
  const WarehouseOperationsTab({super.key});

  @override
  State<WarehouseOperationsTab> createState() => _WarehouseOperationsTabState();
}

class _WarehouseOperationsTabState extends State<WarehouseOperationsTab> {
  bool _loading = true;
  bool _stockEntry = false;
  bool _stockReconciliation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPermissions());
  }

  Future<void> _loadPermissions() async {
    final state = context.read<WarehouseStockState>();
    final results = await Future.wait([
      state.canReadDoctype('Stock Entry'),
      state.canCreateDoctype('Stock Entry'),
      state.canReadDoctype('Stock Reconciliation'),
      state.canCreateDoctype('Stock Reconciliation'),
    ]);
    if (!mounted) return;
    setState(() {
      _stockEntry = results[0] || results[1];
      _stockReconciliation = results[2] || results[3];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = <_WarehouseTransactionAction>[
      if (_stockEntry)
        _WarehouseTransactionAction(
          onTap: () => _openStockEntry(context),
          icon: Icons.swap_horiz_rounded,
          title: 'Stock Entry',
          subtitle: 'Transfer, receipt, issue, dan tipe ERPNext lain',
          color: warehouseOrange,
        ),
      if (_stockReconciliation)
        _WarehouseTransactionAction(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StockReconciliationPanel(),
            ),
          ),
          icon: Icons.fact_check_outlined,
          title: 'Stock Reconciliation',
          subtitle: 'Penyesuaian stok ERPNext 15',
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
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (actions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Tidak ada transaksi gudang yang bisa diakses.',
              style: TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
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
