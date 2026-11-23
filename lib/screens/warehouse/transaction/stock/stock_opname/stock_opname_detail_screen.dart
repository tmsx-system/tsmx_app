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

class StockOpnameDetailScreen extends StatefulWidget {
  final String name;

  const StockOpnameDetailScreen({super.key, required this.name});

  @override
  State<StockOpnameDetailScreen> createState() =>
      _StockOpnameDetailScreenState();
}

class _StockOpnameDetailScreenState extends State<StockOpnameDetailScreen> {
  Map<String, dynamic>? _doc;
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
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _canWrite = canWrite;
        _canSubmit = canSubmit;
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
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.softGreen,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.fact_check_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (company.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                company,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            ErpStatusBadge(statusText: statusText),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        'Items',
                        '${lines.length}',
                        Icons.inventory_2_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metric(
                        'Tanggal',
                        when.isEmpty ? '-' : when,
                        Icons.event_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoCard([
                  ('Doc Status', statusText),
                  if (warehouse.isNotEmpty) ('Warehouse', warehouse),
                  if (group.isNotEmpty) ('Item Group', group),
                  if (company.isNotEmpty) ('Company', company),
                  if (penyelesaian.trim().isNotEmpty) ('Status', penyelesaian),
                ]),
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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Detail Item',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.softGreen,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${lines.length} item',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Stock Awal',
                  '${formatStockQty(line.stockAwal)} ${line.uom}',
                  valueColor: const Color(0xFF15803D),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'Stock Fisik',
                  '${formatStockQty(line.stockFisik)} ${line.uom}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _miniStat('Selisih', formatStockQty(line.selisih))),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'Cek',
                  line.sudahDicek ? 'Sudah dicek' : 'Belum',
                ),
              ),
            ],
          ),
          if (line.keterangan.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _miniStat('Keterangan', line.keterangan),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(List<(String, String)> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color? valueColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
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
            style: TextStyle(
              color: valueColor ?? AppColors.navy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
