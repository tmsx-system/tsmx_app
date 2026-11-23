import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_opname.dart';
import '../../../../../state/warehouse/stock_opname_state.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/erp_error_message.dart';
import '../../../../../widgets/erp/erp_status_badge.dart';
import '../../../../../widgets/erp/erp_workflow_helper.dart';
import 'create_stock_opname_screen.dart';
import 'stock_opname_widgets.dart';

class StockOpnameDetailScreen extends StatefulWidget {
  final String name;

  const StockOpnameDetailScreen({super.key, required this.name});

  @override
  State<StockOpnameDetailScreen> createState() =>
      _StockOpnameDetailScreenState();
}

class _StockOpnameDetailScreenState extends State<StockOpnameDetailScreen> {
  Map<String, dynamic>? _doc;
  StockOpnameSettlement? _settlement;
  bool _loading = true;
  bool _busy = false;
  bool _canWrite = false;
  bool _canSubmit = false;
  String? _error;

  StockOpnameState get _api =>
      StockOpnameState(context.read<WarehouseStockState>().appState);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await _api.fetchDetail(widget.name);
      final canWrite = await _api.canWrite();
      final canSubmit = await _api.canSubmit();
      StockOpnameSettlement? settlement;
      final status = int.tryParse(doc['docstatus']?.toString() ?? '') ?? 0;
      if (status == 1) {
        try {
          settlement = await _api.findSettlement(widget.name);
        } catch (_) {
          settlement = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _canWrite = canWrite;
        _canSubmit = canSubmit;
        _settlement = settlement;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateStockOpnameScreen(existingName: widget.name),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _submit() async {
    final doc = _doc;
    if (doc == null || _busy) return;
    final blocked = stockOpnameSubmitError(_api.linesOf(doc));
    if (blocked != null) {
      setState(() => _error = blocked);
      return;
    }
    final ok = await confirmErpAction(
      context,
      title: 'Submit Stock Opname',
      message: 'Submit ${widget.name}?',
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.submit(widget.name);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettlement() async {
    final doc = _doc;
    if (doc == null || _busy) return;
    final status = int.tryParse(doc['docstatus']?.toString() ?? '') ?? 0;
    if (status != 1) {
      setState(
        () => _error = 'Stock Opname harus Submitted terlebih dahulu.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var settlement = _settlement ?? await _api.findSettlement(widget.name);
      if (settlement == null) {
        final lines = _api.linesOf(doc);
        if (lines.isEmpty) {
          throw Exception('Stock Opname tidak memiliki detail SKU.');
        }
        final created = await _api.createSettlement(doc);
        settlement = StockOpnameSettlement(id: created);
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => StockOpnameSettlementScreen(name: settlement!.id),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final lines = doc == null ? const <StockOpnameLine>[] : _api.linesOf(doc);
    final docstatus = int.tryParse(doc?['docstatus']?.toString() ?? '') ?? 0;
    final draft = docstatus == 0;
    final statusText = docstatus == 1
        ? 'Submitted'
        : docstatus == 2
        ? 'Cancelled'
        : 'Draft';
    final settlement = _settlement;
    final settlementLabel = settlement == null
        ? 'Penyelesaian Stock Opname'
        : settlement.docstatus == 1
        ? 'Lihat Penyelesaian'
        : 'Lanjutkan Penyelesaian';
    final company = doc?['company']?.toString() ?? '';
    final warehouse = doc?['warehouse']?.toString() ?? '';
    final group = doc?['item_group']?.toString() ?? '';
    final when = [
      doc?['posting_date']?.toString() ?? '',
      doc?['posting_time']?.toString() ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final penyelesaian = doc?['status_penyelesaian']?.toString() ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Detail Stock Opname',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.name,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          ErpStatusBadge(statusText: statusText),
                        ],
                      ),
                      if (company.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          company,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      StockOpnameMetric(
                        label: 'Tanggal',
                        value: when,
                        icon: Icons.event_rounded,
                      ),
                      const SizedBox(height: 8),
                      StockOpnameMetric(
                        label: 'Warehouse',
                        value: warehouse,
                        icon: Icons.warehouse_outlined,
                      ),
                      const SizedBox(height: 8),
                      StockOpnameMetric(
                        label: 'Item Group',
                        value: group,
                        icon: Icons.category_outlined,
                      ),
                      if (penyelesaian.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        StockOpnameMetric(
                          label: 'Status',
                          value: penyelesaian,
                          icon: Icons.flag_outlined,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Detail (${lines.length})',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                for (final line in lines) _line(line),
                const SizedBox(height: 8),
                if (draft && _canWrite)
                  erpActionButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: _busy ? null : _edit,
                  ),
                if (draft && _canSubmit)
                  erpActionButton(
                    label: 'Submit',
                    icon: Icons.verified_outlined,
                    filled: true,
                    onPressed: _busy ? null : _submit,
                  ),
                if (docstatus == 1)
                  erpActionButton(
                    label: settlementLabel,
                    icon: Icons.assignment_turned_in_outlined,
                    filled: true,
                    onPressed: _busy ? null : _openSettlement,
                  ),
              ],
            ),
    );
  }

  Widget _line(StockOpnameLine line) {
    final title = line.itemName.isEmpty ? line.itemCode : line.itemName;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            line.itemCode,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          StockAwalHighlight(qty: line.stockAwal, uom: line.uom),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Stock Fisik',
                  '${formatStockQty(line.stockFisik)} ${line.uom}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat('Selisih', formatStockQty(line.selisih)),
              ),
            ],
          ),
          if (line.sudahDicek || line.keterangan.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (line.sudahDicek) 'Sudah dicek',
                if (line.keterangan.trim().isNotEmpty) line.keterangan,
              ].join(' · '),
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class StockOpnameSettlementScreen extends StatefulWidget {
  final String name;

  const StockOpnameSettlementScreen({super.key, required this.name});

  @override
  State<StockOpnameSettlementScreen> createState() =>
      _StockOpnameSettlementScreenState();
}

class _StockOpnameSettlementScreenState
    extends State<StockOpnameSettlementScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = StockOpnameState(
        context.read<WarehouseStockState>().appState,
      );
      final doc = await api.fetchSettlement(widget.name);
      if (!mounted) return;
      setState(() => _doc = doc);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final raw = doc?['detail_penyelesaian'];
    final lines = raw is List
        ? [
            for (final row in raw.whereType<Map>())
              if ((row['item_code']?.toString().trim() ?? '').isNotEmpty)
                StockOpnameLine.fromJson(Map<String, dynamic>.from(row)),
          ]
        : const <StockOpnameLine>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Penyelesaian',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  doc?['tanggal_penyelesaian']?.toString() ?? '',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                for (final line in lines)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.itemName.isEmpty ? line.itemCode : line.itemName,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        StockAwalHighlight(qty: line.stockAwal, uom: line.uom),
                        const SizedBox(height: 8),
                        Text(
                          'Fisik ${formatStockQty(line.stockFisik)} · Selisih ${formatStockQty(line.selisih)} ${line.uom}',
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (line.keterangan.trim().isNotEmpty)
                          Text(
                            line.keterangan,
                            style: const TextStyle(
                              color: AppColors.slate,
                              fontWeight: FontWeight.w700,
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

