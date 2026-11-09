import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/warehouse_widgets.dart';
import 'material_request/material_request_purpose.dart';
import 'material_request/material_transfer_request_panel.dart';
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
  bool _stockReconciliation = false;
  bool _materialRequest = false;
  List<StockEntryKind> _entryTypes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPermissions());
  }

  Future<void> _loadPermissions() async {
    setState(() => _loading = true);
    final state = context.read<WarehouseStockState>();
    final results = await Future.wait([
      state.canReadDoctype('Stock Entry'),
      state.canCreateDoctype('Stock Entry'),
      state.canReadDoctype('Stock Reconciliation'),
      state.canCreateDoctype('Stock Reconciliation'),
      state.canReadDoctype('Material Request'),
      state.canCreateDoctype('Material Request'),
    ]);
    final canUseStockEntry = results[0] || results[1];
    var types = const <StockEntryKind>[];
    if (canUseStockEntry) {
      try {
        final rows = await state.fetchStockEntryTypes(forceRefresh: true);
        types = rows.map(StockEntryKind.fromType).toList(growable: false);
      } catch (_) {
        types = const [];
      }
      if (types.isEmpty) {
        types = StockEntryKind.standard;
      }
    }
    if (!mounted) return;
    setState(() {
      _entryTypes = types;
      _stockReconciliation = results[2] || results[3];
      _materialRequest = results[4] || results[5];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockActions = <_WarehouseTransactionAction>[
      for (final kind in _entryTypes)
        _WarehouseTransactionAction(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StockEntryPanel(kind: kind),
            ),
          ),
          icon: kind.icon,
          title: kind.title,
          subtitle: kind.subtitle,
          color: kind.color,
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
    final requestActions = <_WarehouseTransactionAction>[
      if (_materialRequest)
        for (final purpose in MaterialRequestPurpose.all)
          _WarehouseTransactionAction(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MaterialTransferRequestPanel(purpose: purpose.name),
              ),
            ),
            icon: purpose.icon,
            title: purpose.name,
            subtitle: 'Purpose: ${purpose.name}',
            color: purpose.color,
          ),
    ];

    return RefreshIndicator(
      onRefresh: _loadPermissions,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          const WarehouseSectionHeader(
            title: 'Transaksi Gudang',
            subtitle: 'Stock Entry dan Material Request dipisah',
            icon: Icons.store_outlined,
          ),
          warehouseSectionGap,
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (stockActions.isEmpty && requestActions.isEmpty)
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
          else ...[
            if (stockActions.isNotEmpty) ...[
              const _TransactionGroupLabel(
                title: 'Stock Entry',
                subtitle: 'Perpindahan dan penyesuaian stok',
              ),
              const SizedBox(height: 12),
              _TransactionGrid(actions: stockActions),
            ],
            if (requestActions.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _TransactionGroupLabel(
                title: 'Material Request',
                subtitle: 'Purchase, Transfer, Issue, Manufacture, Customer Provided',
              ),
              const SizedBox(height: 12),
              _TransactionGrid(actions: requestActions),
            ],
          ],
        ],
      ),
    );
  }
}

class _TransactionGroupLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _TransactionGroupLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TransactionGrid extends StatelessWidget {
  final List<_WarehouseTransactionAction> actions;

  const _TransactionGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 14,
      childAspectRatio: 0.72,
      children: [
        for (final action in actions)
          WarehouseActionGridCard(
            onTap: action.onTap,
            icon: action.icon,
            title: action.title,
            subtitle: action.subtitle,
            color: action.color,
          ),
      ],
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
