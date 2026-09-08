import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/inventory_item.dart';
import '../../models/stock_ledger_movement.dart';
import '../../state/warehouse/warehouse_stock_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_range_presets.dart';

class ItemStockDetailScreen extends StatefulWidget {
  final InventoryItem item;
  final String? companyLabel;
  final String? areaLabel;

  const ItemStockDetailScreen({
    super.key,
    required this.item,
    this.companyLabel,
    this.areaLabel,
  });

  @override
  State<ItemStockDetailScreen> createState() => _ItemStockDetailScreenState();
}

class _ItemStockDetailScreenState extends State<ItemStockDetailScreen> {
  late DateRangePreset _range;
  StockDatePresetId _preset = StockDatePresetId.monthToDate;

  StockLedgerResult? _result;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _range = DateRangePresets.monthToDateRange();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await context
          .read<WarehouseStockState>()
          .fetchStockLedgerForItem(
            itemCode: widget.item.sku,
            from: _range.from,
            to: _range.to,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _applyPreset(StockDatePresetId preset) {
    late DateRangePreset next;
    switch (preset) {
      case StockDatePresetId.monthToDate:
        next = DateRangePresets.monthToDateRange();
      case StockDatePresetId.last7Days:
        next = DateRangePresets.last7DaysRange();
      case StockDatePresetId.last30Days:
        next = DateRangePresets.last30DaysRange();
      case StockDatePresetId.custom:
        return;
    }
    setState(() {
      _preset = preset;
      _range = next;
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _range.from, end: _range.to),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      _preset = StockDatePresetId.custom;
      _range = DateRangePreset(from: picked.start, to: picked.end);
    });
    _load();
  }

  String _formatQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final contextLabel = [
      if (widget.companyLabel != null && widget.companyLabel!.isNotEmpty)
        widget.companyLabel,
      if (widget.areaLabel != null && widget.areaLabel!.isNotEmpty)
        widget.areaLabel,
    ].join(' · ');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        title: const Text(
          'Item Stock Detail',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildHeader(contextLabel),
            const SizedBox(height: 16),
            _buildDateFilter(),
            const SizedBox(height: 16),
            if (_isLoading) ...[
              const LinearProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
            ],
            if (_error != null) ...[
              _buildErrorBox(_error!),
              const SizedBox(height: 16),
            ],
            if (result != null && !_isLoading) ...[
              _buildSummary(result),
              const SizedBox(height: 16),
              _buildMovementList(result.movements),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String contextLabel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.slate.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.item.sku,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.slate,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.item.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'On hand: ',
                style: TextStyle(fontSize: 12, color: AppColors.slate),
              ),
              Text(
                '${widget.item.quantity} units',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (contextLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Context: $contextLabel (all warehouses)',
              style: const TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'All warehouses',
              style: TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Periode',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.slate,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _isLoading ? null : _pickCustomRange,
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: const Text('Ubah periode'),
              ),
            ],
          ),
          Text(
            DateRangePresets.formatRangeLabel(_range),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip('Bulan ini', StockDatePresetId.monthToDate),
              _presetChip('7 hari', StockDatePresetId.last7Days),
              _presetChip('30 hari', StockDatePresetId.last30Days),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, StockDatePresetId id) {
    final selected = _preset == id;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: _isLoading ? null : (_) => _applyPreset(id),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primary,
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.red,
        ),
      ),
    );
  }

  Widget _buildSummary(StockLedgerResult result) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            label: 'Total masuk',
            value: _formatQty(result.totalIn),
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard(
            label: 'Total keluar',
            value: _formatQty(result.totalOut),
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard(
            label: 'Net',
            value:
                '${result.netQty >= 0 ? '+' : ''}${_formatQty(result.netQty)}',
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppColors.slate,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementList(List<StockLedgerMovement> movements) {
    if (movements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: const Column(
          children: [
            Icon(Icons.swap_vert_rounded, size: 40, color: AppColors.slate),
            SizedBox(height: 10),
            Text(
              'No stock movements in this period',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Try a wider date range.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pergerakan (${movements.length})',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        ...movements.map(_buildMovementRow),
      ],
    );
  }

  Widget _buildMovementRow(StockLedgerMovement m) {
    final qtyColor = m.isIncoming ? Colors.green : Colors.red;
    final qtyPrefix = m.isIncoming ? '+' : '−';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.date,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.slate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  m.voucherType.isEmpty ? 'Stock movement' : m.voucherType,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                if (m.voucherNo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    m.voucherNo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.slate,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  m.warehouse,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.slate),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$qtyPrefix${_formatQty(m.absQty)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: qtyColor,
                ),
              ),
              if (m.qtyAfter != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Saldo: ${_formatQty(m.qtyAfter!)}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
