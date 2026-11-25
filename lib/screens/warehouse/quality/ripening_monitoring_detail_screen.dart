import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/ripening_monitoring.dart';
import '../../../state/warehouse/ripening_monitoring_state.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_status_badge.dart';
import 'create_ripening_monitoring_screen.dart';

class RipeningMonitoringDetailScreen extends StatefulWidget {
  final String name;
  final bool canEdit;
  final bool canSubmit;
  final Future<void> Function() onChanged;

  const RipeningMonitoringDetailScreen({
    super.key,
    required this.name,
    required this.canEdit,
    required this.canSubmit,
    required this.onChanged,
  });

  @override
  State<RipeningMonitoringDetailScreen> createState() =>
      _RipeningMonitoringDetailScreenState();
}

class _RipeningMonitoringDetailScreenState
    extends State<RipeningMonitoringDetailScreen> {
  final _dateFormat = DateFormat('dd MMM yyyy');
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _doc = const {};
  RipeningFieldMap _meta = const RipeningFieldMap();
  List<RipeningLine> _lines = const [];

  RipeningMonitoringState get _api =>
      RipeningMonitoringState(context.read<WarehouseStockState>().appState);

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
      final meta = await _api.resolveMeta();
      final doc = await _api.fetchDetail(widget.name);
      final lines = await _api.loadLines(doc);
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _doc = doc;
        _lines = lines;
      });
    } catch (error) {
      if (mounted) setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateRipeningMonitoringScreen(
          existingName: widget.name,
          company: _doc[_meta.companyField]?.toString(),
        ),
      ),
    );
    if (changed == true) {
      await widget.onChanged();
      if (mounted) await _load();
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await _api.submit(widget.name);
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(captureErpError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _api.totalsOf(_doc, _lines);
    final status = _status(int.tryParse('${_doc['docstatus']}') ?? 0);
    final gassing = _dated(_meta.gassingField, 'gassing');
    final sampling = _dated(_meta.samplingField, 'sampling');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Detail Ripening Monitoring')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Text('🍌', style: TextStyle(fontSize: 22)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.name,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _text(_doc[_meta.companyField]).isEmpty
                                      ? _text(_doc['company'])
                                      : _text(_doc[_meta.companyField]),
                                  style: const TextStyle(
                                    color: AppColors.slate,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ErpStatusBadge(statusText: status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _mini('Tanggal Gassing', _show(gassing))),
                          const SizedBox(width: 8),
                          Expanded(child: _mini('Tanggal Sampling', _show(sampling))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _section('Rekapitulasi'),
                _metric('Total Sampel', _qty(totals.sampel), AppColors.navy),
                _metric('Total Normal', _qty(totals.normal), const Color(0xFF15803D)),
                _metric('Total Blonteng', _qty(totals.blonteng), AppColors.danger),
                _percent('Persentase Normal', totals.persenNormal, const Color(0xFF16A34A)),
                _percent('Persentase Blonteng', totals.persenBlonteng, AppColors.danger),
                const SizedBox(height: 8),
                _section('Detail Pengamatan'),
                if (_lines.isEmpty)
                  const Text(
                    'Belum ada SKU pada dokumen ini.',
                    style: TextStyle(color: AppColors.slate, fontWeight: FontWeight.w700),
                  ),
                for (final line in _lines) _observation(line),
                const SizedBox(height: 4),
                _section('Hasil Pengamatan'),
                for (final line in _lines) _result(line),
                if (widget.canEdit || widget.canSubmit) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (widget.canEdit)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _edit,
                            child: const Text('Edit'),
                          ),
                        ),
                      if (widget.canEdit && widget.canSubmit)
                        const SizedBox(width: 10),
                      if (widget.canSubmit)
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text('Submit'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  String _dated(String field, String hint) {
    final direct = _text(_doc[field]);
    if (direct.isNotEmpty) return direct;
    for (final entry in _doc.entries) {
      if (entry.key.toLowerCase().contains(hint)) return _text(entry.value);
    }
    return '';
  }

  Widget _observation(RipeningLine line) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.itemName.isEmpty ? line.itemCode : line.itemName,
            style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
          ),
          Text(
            line.itemCode,
            style: const TextStyle(color: AppColors.slate, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Posisi Rak', line.posisi.isEmpty ? '-' : line.posisi),
              _stat(_meta.gasLabel, _qty(line.gasEthylene)),
              _stat('Qty Sampel', _qty(line.qtySampel)),
              _stat('RH', '${_qty(line.rh)}%'),
              _stat('Suhu Pulp', '${_qty(line.suhuPulp)}°C'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _result(RipeningLine line) {
    final qty = line.qtySampel;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.itemName.isEmpty ? line.itemCode : line.itemName,
            style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Hijau', '${_qty(line.hijau)} · ${ripeningPercent(line.hijau, qty).toStringAsFixed(2)}%'),
              _stat('Normal', '${_qty(line.normal)} · ${ripeningPercent(line.normal, qty).toStringAsFixed(2)}%'),
              _stat('Kuning', '${_qty(line.kuning)} · ${ripeningPercent(line.kuning, qty).toStringAsFixed(2)}%'),
              _stat('Blonteng', '${_qty(line.blonteng)} · ${ripeningPercent(line.blonteng, qty).toStringAsFixed(2)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _mini(String label, String value) {
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
            style: const TextStyle(color: AppColors.slate, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      width: 148,
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
            style: const TextStyle(color: AppColors.slate, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return _panel(
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.slate, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _percent(String label, double value, Color color) {
    final clamped = value.clamp(0, 100).toDouble();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${_qty(clamped)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: clamped / 100,
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _show(Object? value) {
    final text = _text(value);
    final parsed = DateTime.tryParse(text.length >= 10 ? text.substring(0, 10) : text);
    if (parsed == null) return text.isEmpty ? '-' : text;
    return _dateFormat.format(parsed);
  }
}

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _status(int docstatus) {
  if (docstatus == 1) return 'Submitted';
  if (docstatus == 2) return 'Cancelled';
  return 'Draft';
}
