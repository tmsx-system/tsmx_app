import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/warehouse_tracking_record.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseBatchSerialScreen extends StatelessWidget {
  const WarehouseBatchSerialScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Batch & Serial Tracking',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Batch'),
            Tab(text: 'Serial Number'),
          ],
        ),
      ),
      body: const TabBarView(children: [_BatchView(), _SerialView()]),
    ),
  );
}

class _BatchView extends StatefulWidget {
  const _BatchView();

  @override
  State<_BatchView> createState() => _BatchViewState();
}

class _BatchViewState extends State<_BatchView> {
  final _search = TextEditingController();
  List<WarehouseBatchRecord> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await context.read<WarehouseStockState>().fetchWarehouseBatches(
        forceRefresh: forceRefresh,
      );
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows = _rows.where((row) {
      return query.isEmpty ||
          row.name.toLowerCase().contains(query) ||
          row.itemCode.toLowerCase().contains(query);
    }).toList();
    final expiring = _rows.where((row) {
      if (row.expiryDate == null) return false;
      final days = row.expiryDate!.difference(DateTime.now()).inDays;
      return days >= 0 && days <= 30;
    }).length;
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          const WarehouseSectionHeader(
            title: 'Tracking Batch',
            subtitle: 'Pantau batch item dan tanggal kedaluwarsa',
            icon: Icons.calendar_month_outlined,
          ),
          warehouseSectionGap,
          Row(
            children: [
              Expanded(child: _metric('Total batch', '${_rows.length}')),
              const SizedBox(width: 10),
              Expanded(child: _metric('Expiry <=30 hari', '$expiring')),
            ],
          ),
          const SizedBox(height: 12),
          WarehouseSearchField(
            controller: _search,
            hintText: 'Cari nomor batch atau item',
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            WarehouseInfoPanel(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              message: _error!,
            ),
          ],
          warehouseSectionGap,
          if (rows.isEmpty && !_loading)
            const ErpEmptyState(
              title: 'Batch tidak ditemukan',
              message: 'Tarik ke bawah untuk refresh atau ubah pencarian.',
            )
          else
            ...rows.map(_batchCard),
        ],
      ),
    );
  }

  Widget _batchCard(WarehouseBatchRecord row) {
    final days = row.expiryDate?.difference(DateTime.now()).inDays;
    final expired = days != null && days < 0;
    final warning = days != null && days >= 0 && days <= 30;
    final color = expired
        ? AppColors.danger
        : warning
        ? AppColors.warning
        : AppColors.success;
    final status = row.expiryDate == null
        ? 'Tanpa expiry'
        : expired
        ? 'Expired'
        : warning
        ? '$days hari lagi'
        : DateFormat('dd MMM yyyy').format(row.expiryDate!);
    return _recordCard(
      icon: Icons.inventory_2_outlined,
      title: row.name,
      subtitle: row.itemCode,
      detail: status,
      color: row.disabled ? AppColors.slate : color,
    );
  }
}

class _SerialView extends StatefulWidget {
  const _SerialView();

  @override
  State<_SerialView> createState() => _SerialViewState();
}

class _SerialViewState extends State<_SerialView> {
  final _search = TextEditingController();
  List<WarehouseSerialRecord> _rows = const [];
  String? _warehouse;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      if (state.warehouses.isEmpty) {
        await state.refreshWarehouses();
      }
      _rows = await state.fetchWarehouseSerialNumbers(
        forceRefresh: forceRefresh,
      );
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WarehouseStockState>();
    final query = _search.text.trim().toLowerCase();
    final warehouseSet = <String>{
      ...state.warehouses
          .map((row) => row.name)
          .where((name) => name.isNotEmpty),
      ..._rows.map((row) => row.warehouse).where((name) => name.isNotEmpty),
    };
    final warehouses = warehouseSet.toList()..sort();
    final selectedWarehouse = warehouses.contains(_warehouse)
        ? _warehouse
        : null;
    final rows = _rows.where((row) {
      return (selectedWarehouse == null ||
              row.warehouse == selectedWarehouse) &&
          (query.isEmpty ||
              row.name.toLowerCase().contains(query) ||
              row.itemCode.toLowerCase().contains(query) ||
              row.batchNo.toLowerCase().contains(query));
    }).toList();
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          const WarehouseSectionHeader(
            title: 'Tracking Serial Number',
            subtitle: 'Cari serial number dan lokasi stok terakhir',
            icon: Icons.numbers_rounded,
          ),
          warehouseSectionGap,
          WarehouseSearchField(
            controller: _search,
            hintText: 'Cari serial, item, atau batch',
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedWarehouse,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Filter gudang',
              prefixIcon: Icon(Icons.warehouse_outlined),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Semua gudang')),
              ...warehouses.map(
                (warehouse) => DropdownMenuItem(
                  value: warehouse,
                  child: Text(warehouse, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) => setState(
              () => _warehouse = value?.isEmpty == true ? null : value,
            ),
          ),
          if (warehouses.isEmpty && !_loading) ...[
            const SizedBox(height: 10),
            const WarehouseInfoPanel(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              message:
                  'Master Warehouse belum terbaca. Pastikan role memiliki Select dan Read pada Warehouse.',
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            WarehouseInfoPanel(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              message: _error!,
            ),
          ],
          warehouseSectionGap,
          if (rows.isEmpty && !_loading)
            const ErpEmptyState(
              title: 'Serial number tidak ditemukan',
              message: 'Tarik ke bawah untuk refresh atau ubah filter.',
            )
          else
            ...rows.map(
              (row) => _recordCard(
                icon: Icons.tag_rounded,
                title: row.name,
                subtitle: [
                  row.itemCode,
                  if (row.warehouse.isNotEmpty) row.warehouse,
                  if (row.batchNo.isNotEmpty) 'Batch ${row.batchNo}',
                ].join(' | '),
                detail: row.status.isEmpty
                    ? 'Status tidak tersedia'
                    : row.status,
                color: row.warehouse.isEmpty
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ),
        ],
      ),
    );
  }
}

Widget _metric(String label, String value) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.border),
    boxShadow: AppColors.cardShadow,
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 11)),
    ],
  ),
);

Widget _recordCard({
  required IconData icon,
  required String title,
  required String subtitle,
  required String detail,
  required Color color,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: AppColors.cardShadow,
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          child: Icon(icon),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.slate, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            detail,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  ),
);

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst(RegExp(r'^Exception:\s*'), '')
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
