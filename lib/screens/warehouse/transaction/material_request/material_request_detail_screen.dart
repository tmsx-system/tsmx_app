import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/material_request.dart';
import '../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/erp_doc_utils.dart';
import '../../../../utils/erp_error_message.dart';
import '../../../../widgets/erp/erp_status_badge.dart';
import '../../../../widgets/responsive/responsive_layout.dart';
import 'create_material_transfer_request_screen.dart';
import 'material_request_purpose.dart';

class MaterialRequestDetailScreen extends StatefulWidget {
  final MaterialRequest request;
  final bool canEdit;

  const MaterialRequestDetailScreen({
    super.key,
    required this.request,
    this.canEdit = false,
  });

  @override
  State<MaterialRequestDetailScreen> createState() =>
      _MaterialRequestDetailScreenState();
}

class _MaterialRequestDetailScreenState
    extends State<MaterialRequestDetailScreen> {
  late MaterialRequest _request = widget.request;
  bool _loading = true;
  bool _edited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  MaterialRequestPurpose get _purpose => MaterialRequestPurpose.all.firstWhere(
    (row) => row.name.toLowerCase() == _request.type.toLowerCase(),
    orElse: () => MaterialRequestPurpose.all.first,
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await context
          .read<WarehouseStockState>()
          .frappeService
          .fetchDocument('Material Request', widget.request.id);
      if (!mounted) return;
      setState(() => _request = MaterialRequest.fromJson(doc));
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = captureErpError(
          context,
          error,
          action: 'membuka Material Request',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _request.sourceWarehouse.isNotEmpty
        ? _request.sourceWarehouse
        : _firstItemValue((item) => item.fromWarehouse);
    final target = _request.targetWarehouse.isNotEmpty
        ? _request.targetWarehouse
        : _firstItemValue((item) => item.warehouse);
    final canEdit = widget.canEdit && isDocDraft(_request.docStatus);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_edited);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.primary,
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: _loading ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
        ],
        title: Text(
          _request.id,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 28),
        children: [
          TmsxResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _purpose.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_purpose.icon, color: _purpose.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _request.type,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _purpose.summary,
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ErpStatusBadge(statusText: _request.statusText),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _InfoCard(
                  rows: [
                    _InfoRow('Company', _request.company),
                    _InfoRow('Tanggal', _request.transactionDate),
                    _InfoRow('Required By', _request.scheduleDate),
                    _InfoRow('Status Dokumen', docStatusLabel(_request.docStatus)),
                    if (source != '-') _InfoRow('Gudang Asal', source),
                    if (target != '-') _InfoRow('Gudang Tujuan', target),
                    _InfoRow('Total Qty', _request.totalQty.toString()),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 3)
                else if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  _InfoCard(
                    title: 'Items',
                    rows: [
                      for (final item in _request.items)
                        _InfoRow(
                          item.itemName.isEmpty ? item.itemCode : item.itemName,
                          '${item.qty} ${item.uom}'.trim(),
                          subtitle: [
                            item.itemCode,
                            if (item.fromWarehouse.isNotEmpty)
                              'Dari ${item.fromWarehouse}',
                            if (item.warehouse.isNotEmpty) 'Ke ${item.warehouse}',
                          ].join(' · '),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMaterialTransferRequestScreen(
          purpose: _request.type.isEmpty ? widget.request.type : _request.type,
          existingName: _request.id,
        ),
      ),
    );
    if (changed == true && mounted) {
      _edited = true;
      await _load();
    }
  }

  String _firstItemValue(String Function(MaterialRequestItem item) read) {
    for (final item in _request.items) {
      final value = read(item).trim();
      if (value.isNotEmpty) return value;
    }
    return '-';
  }
}

class _InfoRow {
  final String label;
  final String value;
  final String subtitle;

  const _InfoRow(this.label, this.value, {this.subtitle = ''});
}

class _InfoCard extends StatelessWidget {
  final String? title;
  final List<_InfoRow> rows;

  const _InfoCard({this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final row in rows) ...[
            Text(
              row.label,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              row.value.isEmpty ? '-' : row.value,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                row.subtitle,
                style: const TextStyle(color: AppColors.slate, fontSize: 12),
              ),
            ],
            if (row != rows.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}
