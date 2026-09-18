import 'package:flutter/material.dart';

import 'warehouse_barcode_scanner_screen.dart';
import 'warehouse_batch_serial_screen.dart';
import 'warehouse_operation_history_screen.dart';
import 'warehouse_stock_opname_screen.dart';
import 'warehouse_stock_entry_screen.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseOperationsTab extends StatelessWidget {
  const WarehouseOperationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _WarehouseOperationAction(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const WarehouseOperationHistoryScreen(),
          ),
        ),
        icon: Icons.history_rounded,
        title: 'Riwayat',
        subtitle: 'Transaksi gudang terbaru',
        color: warehouseBlue,
      ),
      _WarehouseOperationAction(
        onTap: () => _openOperation(context, WarehouseOperation.transfer),
        operation: WarehouseOperation.transfer,
        subtitle: 'Pindahkan antar gudang',
        color: warehouseOrange,
      ),
      _WarehouseOperationAction(
        onTap: () => _openOperation(context, WarehouseOperation.receive),
        operation: WarehouseOperation.receive,
        subtitle: 'Barang masuk gudang',
        color: warehouseGreen,
      ),
      _WarehouseOperationAction(
        onTap: () => _openOperation(context, WarehouseOperation.issue),
        operation: WarehouseOperation.issue,
        subtitle: 'Barang keluar gudang',
        color: warehouseCyan,
      ),
      _WarehouseOperationAction(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WarehouseStockOpnameScreen()),
        ),
        icon: Icons.inventory_outlined,
        title: 'Stock Opname',
        subtitle: 'Hitung stok fisik',
        color: warehousePurple,
      ),
      _WarehouseOperationAction(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const WarehouseBarcodeScannerScreen(),
          ),
        ),
        icon: Icons.qr_code_scanner_rounded,
        title: 'Barcode',
        subtitle: 'Scan item dan stok',
        color: warehouseGreen,
      ),
      _WarehouseOperationAction(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WarehouseBatchSerialScreen()),
        ),
        icon: Icons.numbers_rounded,
        title: 'Batch Serial',
        subtitle: 'Tracking batch dan expiry',
        color: warehouseBlue,
      ),
    ];

    return ListView(
      padding: warehousePagePaddingOf(context),
      children: [
        const WarehouseSectionHeader(
          title: 'Operasi Gudang',
          subtitle: 'Transfer, penerimaan, pengeluaran, dan stock opname',
          icon: Icons.swap_horiz_rounded,
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

  void _openOperation(BuildContext context, WarehouseOperation operation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseStockEntryScreen(operation: operation),
      ),
    );
  }
}

class _WarehouseOperationAction {
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  _WarehouseOperationAction({
    required this.onTap,
    IconData? icon,
    String? title,
    required this.subtitle,
    required this.color,
    WarehouseOperation? operation,
  }) : icon = icon ?? operation!.icon,
       title = title ?? operation!.title;
}
