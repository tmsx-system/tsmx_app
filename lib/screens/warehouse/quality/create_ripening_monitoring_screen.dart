import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/ripening_monitoring.dart';
import '../../../state/warehouse/ripening_monitoring_state.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';

class CreateRipeningMonitoringScreen extends StatefulWidget {
  final String? company;
  final String? existingName;

  const CreateRipeningMonitoringScreen({
    super.key,
    this.company,
    this.existingName,
  });

  @override
  State<CreateRipeningMonitoringScreen> createState() =>
      _CreateRipeningMonitoringScreenState();
}

class _CreateRipeningMonitoringScreenState
    extends State<CreateRipeningMonitoringScreen> {
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _lines = <_RipeningEditors>[];
  List<String> _companies = const [];
  RipeningFieldMap _meta = const RipeningFieldMap();
  String? _company;
  String? _series;
  DateTime _gassing = DateTime.now();
  DateTime _sampling = DateTime.now();
  bool _isGroup = false;
  String? _oldParent;
  String? _parentMonitoring;
  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => (widget.existingName ?? '').trim().isNotEmpty;

  RipeningMonitoringState get _api =>
      RipeningMonitoringState(context.read<WarehouseStockState>().appState);

  @override
  void initState() {
    super.initState();
    final company = widget.company?.trim() ?? '';
    _company = company.isEmpty ? null : company;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final app = context.read<WarehouseStockState>().appState;
      await app.loadSellingFilterOptions();
      final meta = await _api.resolveMeta();
      final series = await _api.fetchNamingSeries();
      if (!mounted) return;
      final companies = app.sellingCompanies;
      _meta = meta;
      _companies = companies;
      _series ??= series.isNotEmpty ? series.first : null;
      _company ??= app.preferredCompany(companies) ??
          (companies.isNotEmpty ? companies.first : null);
      if (_isEdit) {
        final doc = await _api.fetchDetail(widget.existingName!.trim());
        _company = _text(doc[meta.companyField]).isEmpty
            ? _company
            : _text(doc[meta.companyField]);
        _gassing = _readDate(doc[meta.gassingField]) ?? _gassing;
        _sampling = _readDate(doc[meta.samplingField]) ?? _sampling;
        _isGroup = doc['is_group'] == 1 || doc['is_group'] == true;
        _oldParent = _text(doc['old_parent']);
        _parentMonitoring = _text(doc['parent_ripening_monitoring']);
        if (_oldParent!.isEmpty) _oldParent = null;
        if (_parentMonitoring!.isEmpty) _parentMonitoring = null;
        _series = _text(doc[meta.seriesField]).isEmpty
            ? _series
            : _text(doc[meta.seriesField]);
        _setLines(await _api.loadLines(doc));
      } else {
        _setLines(await _api.defaultLines());
      }
    } catch (error) {
      if (mounted) setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setLines(List<RipeningLine> lines) {
    for (final line in _lines) {
      line.dispose();
    }
    _lines
      ..clear()
      ..addAll(lines.map(_RipeningEditors.fromLine));
    if (_lines.isNotEmpty) _lines.first.open = true;
  }

  Future<void> _pickDate({required bool gassing}) async {
    final current = gassing ? _gassing : _sampling;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (gassing) {
        _gassing = picked;
      } else {
        _sampling = picked;
      }
    });
  }

  Future<void> _addItem() async {
    final picked = await showModalBottomSheet<({String code, String name})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ItemSearchSheet(search: _api.searchItems),
    );
    if (picked == null || !mounted) return;
    if (_lines.any((line) => line.itemCode == picked.code)) {
      setState(() => _error = '${picked.name} sudah ada di daftar.');
      return;
    }
    setState(() {
      _error = null;
      for (final line in _lines) {
        line.open = false;
      }
      _lines.add(
        _RipeningEditors.fromLine(
          RipeningLine(itemCode: picked.code, itemName: picked.name),
        )..open = true,
      );
    });
  }

  List<RipeningLine> _draftLines() => [for (final line in _lines) line.toLine()];

  String? _validateDraft() {
    if ((_company ?? '').trim().isEmpty) return 'Company wajib dipilih.';
    if (_sampling.isBefore(DateTime(_gassing.year, _gassing.month, _gassing.day))) {
      return 'Tanggal Sampling tidak boleh sebelum Tanggal Gassing.';
    }
    final lines = _draftLines().where((line) => line.itemCode.trim().isNotEmpty);
    if (lines.isEmpty) return 'Tambahkan minimal satu SKU.';
    final codes = <String>{};
    for (final line in lines) {
      if (!codes.add(line.itemCode.trim())) {
        return 'Item ${line.itemCode} duplikat.';
      }
      if (!line.colorsMatchSample) {
        return 'Item ${line.itemCode}: total kategori tidak boleh melebihi Qty Sampel.';
      }
    }
    return null;
  }

  void _openOnly(_RipeningEditors line) {
    setState(() {
      final next = !line.open;
      for (final row in _lines) {
        row.open = false;
      }
      line.open = next;
    });
  }

  Future<void> _save({required bool submit}) async {
    final problem = _validateDraft();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = RipeningDraft(
        namingSeries: _series,
        company: _company!.trim(),
        tanggalGassing: _gassing,
        tanggalSampling: _sampling,
        isGroup: _isGroup,
        oldParent: _oldParent ?? '',
        parentMonitoring: _parentMonitoring ?? '',
        lines: _draftLines(),
      );
      final name = _isEdit
          ? widget.existingName!.trim()
          : await _api.create(draft);
      if (_isEdit) await _api.update(name, draft);
      if (submit) await _api.submit(name);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Ripening Monitoring' : 'Ripening Monitoring'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                _StepHeader(step: _step),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (_step == 0) ..._detailStep(),
                      if (_step == 1) ..._resultStep(),
                      if (_step == 2) ..._summaryStep(),
                    ],
                  ),
                ),
                _footer(),
              ],
            ),
    );
  }

  List<Widget> _detailStep() {
    return [
      if (_companies.isNotEmpty)
        ErpSearchableFilterField(
          label: 'Company',
          selectedId: _companies.contains(_company) ? _company : null,
          options: [
            for (final company in _companies)
              ErpItemOption(id: company, label: company),
          ],
          decoration: _soDecoration('Company'),
          onSelected: (value) => setState(() => _company = value),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _dateButton(
              'Tanggal Gassing',
              _gassing,
              () => _pickDate(gassing: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dateButton(
              'Tanggal Sampling',
              _sampling,
              () => _pickDate(gassing: false),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const _SectionTitle(index: '1', title: 'Detail Pengamatan'),
      for (final line in _lines) _detailCard(line),
      OutlinedButton.icon(
        onPressed: _saving ? null : _addItem,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah SKU'),
      ),
    ];
  }

  Widget _detailCard(_RipeningEditors line) {
    return         _ItemCard(
          title: line.itemName.isEmpty ? line.itemCode : line.itemName,
          code: line.itemCode,
          open: line.open,
          onToggle: () => _openOnly(line),
          child: Column(
        children: [
          _field(line.posisi, 'Posisi Rak *'),
          Row(
            children: [
              Expanded(child: _number(line.gas, '${_meta.gasLabel} *')),
              const SizedBox(width: 10),
              Expanded(child: _number(line.qty, 'Qty Sampel *', whole: true)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _number(line.rh, 'RH *', suffix: '%')),
              const SizedBox(width: 10),
              Expanded(child: _number(line.suhu, 'Suhu Pulp *', suffix: '°C')),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _resultStep() {
    return [
      const _SectionTitle(index: '2', title: 'Hasil Pengamatan'),
      for (final line in _lines)
        _ItemCard(
          title: line.itemName.isEmpty ? line.itemCode : line.itemName,
          code: line.itemCode,
          open: line.open,
          onToggle: () => _openOnly(line),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _resultField(line.hijau, line.qty, 'Hijau')),
                  const SizedBox(width: 10),
                  Expanded(child: _resultField(line.normal, line.qty, 'Normal')),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _resultField(line.kuning, line.qty, 'Kuning')),
                  const SizedBox(width: 10),
                  Expanded(child: _resultField(line.blonteng, line.qty, 'Blonteng')),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _summaryStep() {
    final totals = RipeningTotals.fromLines(_draftLines());
    final persenNormal = totals.persenNormal.clamp(0, 100).toDouble();
    final persenBlonteng = totals.persenBlonteng.clamp(0, 100).toDouble();
    return [
      const _SectionTitle(index: '3', title: 'Rekapitulasi'),
      _metric('Total Sampel', _qty(totals.sampel), AppColors.navy),
      _metric('Total Normal', _qty(totals.normal), const Color(0xFF15803D)),
      _metric('Total Blonteng', _qty(totals.blonteng), AppColors.danger),
      _percentBar('Persentase Normal', persenNormal, const Color(0xFF16A34A)),
      _percentBar('Persentase Blonteng', persenBlonteng, AppColors.danger),
      const SizedBox(height: 8),
      Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => setState(() => _isGroup = !_isGroup),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _isGroup,
                  activeColor: AppColors.primary,
                  onChanged: (value) => setState(() => _isGroup = value ?? false),
                ),
                const Expanded(
                  child: Text(
                    'Is Group',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _monitoringPicker(
        label: 'Old Parent',
        selectedId: _oldParent,
        onSelected: (value) => setState(() => _oldParent = value),
      ),
      const SizedBox(height: 10),
      _monitoringPicker(
        label: 'Parent Ripening Monitoring',
        selectedId: _parentMonitoring,
        onSelected: (value) => setState(() => _parentMonitoring = value),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: totals.valid ? const Color(0xFFECFDF3) : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: totals.valid ? const Color(0xFF86EFAC) : const Color(0xFFFDBA74),
          ),
        ),
        child: Row(
          children: [
            Icon(
              totals.valid ? Icons.verified_rounded : Icons.error_outline_rounded,
              color: totals.valid ? const Color(0xFF15803D) : const Color(0xFFC2410C),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    totals.valid ? 'Data Sesuai' : 'Data belum sesuai',
                    style: TextStyle(
                      color: totals.valid
                          ? const Color(0xFF166534)
                          : const Color(0xFF9A3412),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totals.valid
                        ? 'Total kategori tidak melebihi Qty Sampel. Persentase dihitung otomatis.'
                        : 'Total Hijau, Normal, Kuning, dan Blonteng tidak boleh melebihi Qty Sampel.',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _monitoringPicker({
    required String label,
    required String? selectedId,
    required ValueChanged<String?> onSelected,
  }) {
    final current = (selectedId ?? '').trim();
    return ErpSearchableFilterField(
      label: label,
      selectedId: current.isEmpty ? null : current,
      allLabel: 'Kosong',
      options: [
        if (current.isNotEmpty) ErpItemOption(id: current, label: current),
      ],
      decoration: _soDecoration(label),
      onSearch: (query) async {
        final names = await _api.searchDocuments(query);
        final self = (widget.existingName ?? '').trim();
        return [
          for (final name in names)
            if (name != self) ErpItemOption(id: name, label: name),
        ];
      },
      onSelected: onSelected,
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _step -= 1),
                  child: const Text('Kembali'),
                ),
              ),
            if (_step > 0) const SizedBox(width: 10),
            if (_step < 2)
              Expanded(
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (_step == 0) {
                            final problem = _validateDraft();
                            if (problem != null) {
                              setState(() => _error = problem);
                              return;
                            }
                          }
                          setState(() {
                            _error = null;
                            _step += 1;
                          });
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Lanjut'),
                ),
              ),
            if (_step == 2)
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(submit: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dateButton(String label, DateTime value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _soDecoration(label),
        child: Text(
          _dateFormat.format(value),
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  InputDecoration _soDecoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.3),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        decoration: _soDecoration(label),
      ),
    );
  }

  Widget _number(
    TextEditingController controller,
    String label, {
    String? suffix,
    bool whole = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: !whole),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            whole ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]'),
          ),
        ],
        decoration: _soDecoration(label, suffix: suffix),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _resultField(
    TextEditingController controller,
    TextEditingController qty,
    String label,
  ) {
    final percent = ripeningPercent(
      _RipeningEditors.read(controller),
      _RipeningEditors.read(qty),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _number(controller, label, whole: true),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Persentase ${percent.toStringAsFixed(2)}%',
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _percentBar(String label, double value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_qty(value)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;

  const _StepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Detail\nPengamatan', 'Hasil\nPengamatan', 'Rekapitulasi'];
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: step >= i ? AppColors.primary : AppColors.border,
                ),
              ),
            Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: step >= i
                      ? AppColors.primary
                      : AppColors.surfaceMuted,
                  child: step > i
                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: step >= i ? Colors.white : AppColors.slate,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: step == i ? AppColors.primary : AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String index;
  final String title;

  const _SectionTitle({required this.index, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.softGreen,
            child: Text(
              index,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final String title;
  final String code;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  const _ItemCard({
    required this.title,
    required this.code,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: open ? AppColors.primaryLight : AppColors.border),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFEF3C7),
              child: Text('🍌', style: TextStyle(fontSize: 20)),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(code),
            trailing: Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _ItemSearchSheet extends StatefulWidget {
  final Future<List<({String code, String name})>> Function(String query) search;

  const _ItemSearchSheet({required this.search});

  @override
  State<_ItemSearchSheet> createState() => _ItemSearchSheetState();
}

class _ItemSearchSheetState extends State<_ItemSearchSheet> {
  final _query = TextEditingController();
  List<({String code, String name})> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(String query) async {
    setState(() => _loading = true);
    try {
      final rows = await widget.search(query);
      if (mounted) setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Cari SKU',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: _run,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final row in _rows)
                          ListTile(
                            title: Text(row.name),
                            subtitle: Text(row.code),
                            onTap: () => Navigator.pop(context, row),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RipeningEditors {
  final String itemCode;
  final String itemName;
  final TextEditingController posisi;
  final TextEditingController gas;
  final TextEditingController qty;
  final TextEditingController rh;
  final TextEditingController suhu;
  final TextEditingController ruang;
  final TextEditingController hijau;
  final TextEditingController normal;
  final TextEditingController kuning;
  final TextEditingController blonteng;
  bool open = false;

  _RipeningEditors({
    required this.itemCode,
    required this.itemName,
    required this.posisi,
    required this.gas,
    required this.qty,
    required this.rh,
    required this.suhu,
    required this.ruang,
    required this.hijau,
    required this.normal,
    required this.kuning,
    required this.blonteng,
  });

  factory _RipeningEditors.fromLine(RipeningLine line) {
    return _RipeningEditors(
      itemCode: line.itemCode,
      itemName: line.itemName,
      posisi: TextEditingController(text: line.posisi),
      gas: TextEditingController(text: _qty(line.gasEthylene)),
      qty: TextEditingController(text: _qty(line.qtySampel)),
      rh: TextEditingController(text: _qty(line.rh)),
      suhu: TextEditingController(text: _qty(line.suhuPulp)),
      ruang: TextEditingController(text: line.ruang),
      hijau: TextEditingController(text: _qty(line.hijau)),
      normal: TextEditingController(text: _qty(line.normal)),
      kuning: TextEditingController(text: _qty(line.kuning)),
      blonteng: TextEditingController(text: _qty(line.blonteng)),
    );
  }

  RipeningLine toLine() {
    return RipeningLine(
      itemCode: itemCode,
      itemName: itemName,
      posisi: posisi.text.trim(),
      gasEthylene: read(gas),
      qtySampel: read(qty),
      rh: read(rh),
      suhuPulp: read(suhu),
      ruang: ruang.text.trim(),
      hijau: read(hijau),
      normal: read(normal),
      kuning: read(kuning),
      blonteng: read(blonteng),
    );
  }

  static double read(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  void dispose() {
    posisi.dispose();
    gas.dispose();
    qty.dispose();
    rh.dispose();
    suhu.dispose();
    ruang.dispose();
    hijau.dispose();
    normal.dispose();
    kuning.dispose();
    blonteng.dispose();
  }
}

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _text(Object? value) => value?.toString().trim() ?? '';

DateTime? _readDate(Object? value) {
  final text = _text(value);
  if (text.length < 10) return null;
  return DateTime.tryParse(text.substring(0, 10));
}
