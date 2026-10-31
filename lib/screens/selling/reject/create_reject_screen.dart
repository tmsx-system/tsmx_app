import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/reject.dart';
import '../../../state/selling/reject_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../shared/sales_attachment_card.dart';
import '../shared/sales_ui.dart';

class CreateRejectScreen extends StatefulWidget {
  final String? existingName;

  const CreateRejectScreen({super.key, this.existingName});

  @override
  State<CreateRejectScreen> createState() =>
      _CreateRejectScreenState();
}

class _CreateRejectScreenState extends State<CreateRejectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keteranganCtrl = TextEditingController();
  final _rows = <_ItemRow>[];
  final _imagePicker = ImagePicker();
  final _photos = <XFile>[];

  bool _loading = true;
  bool _saving = false;
  bool _workflowBusy = false;
  String? _error;
  String? _series;
  List<String> _seriesOptions = const [];
  String? _company;
  String? _customer;
  DateTime _postingDate = DateTime.now();
  String? _workflowState;
  String? _stockEntry;
  String? _savedName;
  List<String> _workflowActions = const [];
  Map<String, dynamic>? _loadedDocument;
  final _itemMeta = <String, ({String name, String uom})>{};
  List<String> _existingAttachmentNames = const [];

  bool get _isEdit =>
      (widget.existingName ?? '').trim().isNotEmpty ||
      (_savedName ?? '').trim().isNotEmpty;

  String? get _documentName {
    final existing = widget.existingName?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    final saved = _savedName?.trim() ?? '';
    return saved.isEmpty ? null : saved;
  }

  @override
  void initState() {
    super.initState();
    _rows.add(_ItemRow());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keteranganCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<RejectState>();
      final companies = state.sellingCompanies;
      _company ??= state.preferredCompany(companies) ??
          (companies.isNotEmpty ? companies.first : null);

      // Meta + naming series in parallel (create/edit bootstrap).
      final boot = await Future.wait<Object?>([
        state.resolveMeta().then<Object?>((_) => null).catchError((_) => null),
        state.fetchNamingSeries().then<Object?>((v) => v).catchError((_) => null),
      ]);
      final series = boot[1];
      if (series is List<String>) {
        _seriesOptions = series;
        _series ??= _seriesOptions.isNotEmpty ? _seriesOptions.first : null;
      } else {
        _seriesOptions = const [];
      }

      if (_documentName != null) {
        await _applyExisting(state, _documentName!);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyExisting(RejectState state, String name) async {
    final doc = await state.fetchDetail(name);
    _loadedDocument = doc;
    _series = doc['naming_series']?.toString().trim() ?? _series;
    _company = doc['company']?.toString().trim() ?? _company;
    _customer = doc['customer']?.toString().trim() ?? _customer;
    _workflowState = doc['workflow_state']?.toString().trim();
    _stockEntry = doc['stock_entry']?.toString().trim();
    _keteranganCtrl.text = doc['keterangan']?.toString() ?? '';
    try {
      final files = await state.fetchAttachments(name);
      _existingAttachmentNames = [
        for (final row in files)
          () {
            final fileName = row['file_name']?.toString().trim() ?? '';
            if (fileName.isNotEmpty) return fileName;
            return row['name']?.toString().trim() ?? '';
          }(),
      ].where((item) => item.isNotEmpty).toList();
    } catch (_) {
      _existingAttachmentNames = const [];
    }
    final parsed = DateTime.tryParse(doc['posting_date']?.toString() ?? '');
    if (parsed != null) {
      _postingDate = DateTime(parsed.year, parsed.month, parsed.day);
    }
    final rawItems =
        doc['reject_item'] ?? doc['items'] ?? doc['reject_items'];
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        if (rawItems is List)
          for (final raw in rawItems.whereType<Map>())
            _ItemRow(
              itemCode: raw['item_code']?.toString(),
              itemName: raw['item_name']?.toString() ?? '',
              sourceWarehouse: raw['source_warehouse']?.toString() ??
                  raw['s_warehouse']?.toString() ??
                  raw['warehouse']?.toString(),
              uom: raw['uom']?.toString() ?? '',
              qtyText: () {
                final qty = double.tryParse(raw['qty']?.toString() ?? '') ?? 1;
                return qty == qty.roundToDouble()
                    ? qty.toInt().toString()
                    : qty.toString();
              }(),
            ),
      ]);
    if (_rows.isEmpty) _rows.add(_ItemRow());

    // Transitions from the same doc — skip extra GET.
    try {
      _workflowActions = await state.fetchWorkflowActionsForDocument(doc);
    } catch (_) {
      _workflowActions = const [];
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _postingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() => _postingDate = picked);
  }

  Future<List<ErpItemOption>> _searchCustomers(String query) async {
    final rows = await context.read<RejectState>().searchCustomers(
      query: query,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString(),
            label: (row['customer_name']?.toString().trim().isNotEmpty == true)
                ? '${row['customer_name']} (${row['name']})'
                : row['name'].toString(),
          ),
    ];
  }

  Future<List<ErpItemOption>> _searchItems(String query) async {
    final rows =
        await context.read<RejectState>().searchItems(query: query);
    for (final row in rows) {
      final id = row['name']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      _itemMeta[id] = (
        name: row['item_name']?.toString() ?? '',
        uom: row['stock_uom']?.toString() ?? '',
      );
    }
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString(),
            label: (row['item_name']?.toString().trim().isNotEmpty == true)
                ? '${row['item_name']} (${row['name']})'
                : row['name'].toString(),
          ),
    ];
  }

  Future<List<ErpItemOption>> _searchWarehouses(String query) async {
    final rows = await context.read<RejectState>().searchWarehouses(
      query: query,
      company: _company,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString(),
            label: (row['warehouse_name']?.toString().trim().isNotEmpty == true)
                ? '${row['warehouse_name']} (${row['name']})'
                : row['name'].toString(),
          ),
    ];
  }

  Future<void> _pickCamera() async {
    final photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (photo != null && mounted) setState(() => _photos.add(photo));
  }

  Future<void> _pickGallery() async {
    final photos = await _imagePicker.pickMultiImage(
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (photos.isNotEmpty && mounted) {
      setState(() => _photos.addAll(photos));
    }
  }

  Future<int> _uploadPhotos(RejectState state, String name) async {
    var failed = 0;
    for (final photo in _photos) {
      try {
        await state.uploadAttachment(name, photo.path);
      } catch (_) {
        failed++;
      }
    }
    return failed;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final filled = _rows
        .where((row) => (row.itemCode ?? '').trim().isNotEmpty)
        .toList();
    if ((_company ?? '').trim().isEmpty) {
      setState(() => _error = 'Company wajib dipilih.');
      return;
    }
    if ((_customer ?? '').trim().isEmpty) {
      setState(() => _error = 'Customer wajib dipilih.');
      return;
    }
    if (filled.isEmpty) {
      setState(() => _error = 'Tambahkan minimal satu item.');
      return;
    }
    for (var i = 0; i < filled.length; i++) {
      final row = filled[i];
      if ((row.sourceWarehouse ?? '').trim().isEmpty) {
        setState(() => _error = 'Item ${i + 1}: Source Warehouse wajib.');
        return;
      }
      if (row.qty <= 0) {
        setState(() => _error = 'Item ${i + 1}: Qty harus lebih dari 0.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = RejectDraft(
        namingSeries: _series,
        postingDate: _postingDate,
        company: _company!.trim(),
        customer: _customer!.trim(),
        keterangan: _keteranganCtrl.text,
        items: [
          for (final row in filled)
            RejectItemDraft(
              itemCode: row.itemCode!,
              itemName: row.itemName,
              sourceWarehouse: row.sourceWarehouse!,
              qty: row.qty,
              uom: row.uom,
            ),
        ],
      );
      final state = context.read<RejectState>();
      final existing = _documentName;
      final String savedName;
      final bool createdNew;
      if (existing != null) {
        await state.update(existing, draft);
        savedName = existing;
        createdNew = false;
      } else {
        final created = await state.create(draft);
        final name = created['name']?.toString().trim() ?? '';
        if (name.isEmpty) {
          throw Exception('ERP tidak mengembalikan nomor dokumen.');
        }
        savedName = name;
        createdNew = true;
        if (!mounted) return;
        setState(() {
          _savedName = name;
          _workflowState = created['workflow_state']?.toString() ?? 'Draft';
        });
      }
      final failedUploads = await _uploadPhotos(state, savedName);
      if (!mounted) return;
      final savedLabel = createdNew ? 'dibuat' : 'diperbarui';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedUploads > 0
                ? 'Reject $savedName berhasil $savedLabel, tetapi $failedUploads foto gagal diunggah.'
                : 'Reject $savedName berhasil $savedLabel.',
          ),
          backgroundColor: failedUploads > 0
              ? AppColors.warning
              : AppColors.primary,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runWorkflow(String action) async {
    final name = _documentName;
    if (name == null || _workflowBusy) return;
    final lower = action.toLowerCase();
    final needsReason = lower.contains('reject') ||
        lower.contains('tolak') ||
        lower.contains('decline');
    var reason = '';
    if (needsReason) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Alasan',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lanjut'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = controller.text.trim();
      if (reason.isEmpty) {
        setState(() => _error = 'Alasan wajib diisi untuk $action.');
        return;
      }
    } else {
      final confirmed = await confirmErpAction(
        context,
        title: '$action?',
        message: 'Jalankan "$action" untuk $name?',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _workflowBusy = true);
    if (!mounted) return;
    final rejectState = context.read<RejectState>();
    final ok = await runErpWorkflowAction(
      context,
      action: () => rejectState.applyDocumentWorkflow(
            name: name,
            action: action,
            reason: reason,
            currentDocument: _loadedDocument,
          ),
      successMessage: '$action berhasil untuk $name.',
    );
    if (!mounted) return;
    setState(() => _workflowBusy = false);
    if (ok) {
      await _load();
      if (mounted) Navigator.pop(context, true);
    }
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: AppColors.background,
      isDense: true,
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RejectState>();
    final companies = state.sellingCompanies;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _isEdit ? 'Edit Reject' : 'Buat Reject',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: SalesUi.compactScreenPaddingOf(context).copyWith(
                  bottom: 24 + bottomInset,
                ),
                children: [
                  _section(
                    title: 'Informasi Dokumen',
                    children: [
                      if (_seriesOptions.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey('series-${_series ?? 'none'}'),
                          initialValue: _seriesOptions.contains(_series)
                              ? _series
                              : null,
                          isExpanded: true,
                          decoration: _decoration('Series'),
                          items: [
                            for (final series in _seriesOptions)
                              DropdownMenuItem(
                                value: series,
                                child: Text(
                                  series,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _series = value),
                        ),
                        const SizedBox(height: 14),
                      ],
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: InputDecorator(
                          decoration: _decoration(
                            'Posting Date *',
                            suffix: const Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                              color: AppColors.slate,
                            ),
                          ),
                          child: Text(
                            DateFormat('dd-MM-yyyy').format(_postingDate),
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ErpItemAutocompleteField(
                        label: 'Company *',
                        selectedId: companies.contains(_company)
                            ? _company
                            : null,
                        decoration: _decoration('Company *'),
                        options: [
                          for (final company in companies)
                            ErpItemOption(id: company, label: company),
                        ],
                        onSelected: (value) => setState(() {
                          _company = value;
                          for (final row in _rows) {
                            row.sourceWarehouse = null;
                          }
                        }),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Company wajib'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      ErpItemAutocompleteField(
                        key: ValueKey('customer-${_customer ?? ''}'),
                        label: 'Customer *',
                        selectedId: _customer,
                        decoration: _decoration('Customer *'),
                        options: [
                          if ((_customer ?? '').isNotEmpty)
                            ErpItemOption(
                              id: _customer!,
                              label: _customer!,
                            ),
                        ],
                        onSearch: _searchCustomers,
                        onSelected: (value) =>
                            setState(() => _customer = value),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Customer wajib'
                                : null,
                      ),
                      if ((_workflowState ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: _decoration('Workflow State'),
                          child: Text(
                            _workflowState!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      if ((_stockEntry ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: _decoration('Stock Entry'),
                          child: Text(
                            _stockEntry!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _keteranganCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _decoration(
                          'Keterangan',
                          hint: 'Catatan (opsional)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Reject Item',
                    children: [
                      for (var i = 0; i < _rows.length; i++) ...[
                        _itemCard(i),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _rows.add(_ItemRow())),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Row'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SalesAttachmentCard(
                    title: 'Attachment',
                    existingNames: _existingAttachmentNames,
                    photos: _photos,
                    onCamera: _saving ? null : _pickCamera,
                    onGallery: _saving ? null : _pickGallery,
                    onRemove: (index) => setState(() => _photos.removeAt(index)),
                  ),
                  if (_workflowActions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _section(
                      title: 'Workflow',
                      children: [
                        for (final action in _workflowActions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: erpActionButton(
                              label: action,
                              icon: _workflowIcon(action),
                              filled: action.toLowerCase().contains('approve') ||
                                  action.toLowerCase().contains('submit') ||
                                  action.toLowerCase().contains('revise'),
                              onPressed: _workflowBusy || _saving
                                  ? null
                                  : () => _runWorkflow(action),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _saving
                          ? 'Menyimpan...'
                          : (_isEdit ? 'Update' : 'Simpan'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  IconData _workflowIcon(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('reject') || lower.contains('tolak')) {
      return Icons.cancel_outlined;
    }
    if (lower.contains('revise') || lower.contains('revisi')) {
      return Icons.edit_outlined;
    }
    if (lower.contains('submit') || lower.contains('approve')) {
      return Icons.check_circle_outline_rounded;
    }
    return Icons.play_circle_outline_rounded;
  }

  Widget _itemCard(int index) {
    final row = _rows[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Item ${index + 1}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_rows.length > 1)
                IconButton(
                  tooltip: 'Hapus baris',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _rows.removeAt(index).dispose();
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ErpItemAutocompleteField(
            key: ValueKey('item-$index-${row.itemCode ?? ''}'),
            label: 'Item Code *',
            selectedId: row.itemCode,
            decoration: _decoration('Item Code *'),
            options: [
              if ((row.itemCode ?? '').isNotEmpty)
                ErpItemOption(
                  id: row.itemCode!,
                  label: row.itemName.isEmpty
                      ? row.itemCode!
                      : '${row.itemName} (${row.itemCode})',
                ),
            ],
            onSearch: _searchItems,
            onSelected: (value) async {
              if (value == null) {
                setState(() {
                  row.itemCode = null;
                  row.itemName = '';
                  row.uom = '';
                });
                return;
              }
              if (!_itemMeta.containsKey(value)) {
                await _searchItems(value);
              }
              final meta = _itemMeta[value];
              setState(() {
                row.itemCode = value;
                row.itemName = meta?.name ?? '';
                row.uom = meta?.uom ?? row.uom;
              });
            },
          ),
          if (row.itemName.isNotEmpty) ...[
            const SizedBox(height: 12),
            InputDecorator(
              decoration: _decoration('Item Name'),
              child: Text(
                row.itemName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ErpItemAutocompleteField(
            key: ValueKey('wh-$index-${row.sourceWarehouse ?? ''}'),
            label: 'Source Warehouse *',
            selectedId: row.sourceWarehouse,
            decoration: _decoration('Source Warehouse *'),
            options: [
              if ((row.sourceWarehouse ?? '').isNotEmpty)
                ErpItemOption(
                  id: row.sourceWarehouse!,
                  label: row.sourceWarehouse!,
                ),
            ],
            onSearch: _searchWarehouses,
            onSelected: (value) =>
                setState(() => row.sourceWarehouse = value),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 340;
              final qtyField = TextFormField(
                controller: row.qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('Qty *'),
                validator: (value) {
                  if ((row.itemCode ?? '').isEmpty) return null;
                  final qty = double.tryParse(value?.trim() ?? '');
                  return qty == null || qty <= 0 ? 'Qty > 0' : null;
                },
              );
              final uomField = InputDecorator(
                decoration: _decoration('UOM'),
                child: Text(
                  row.uom.isEmpty ? '-' : row.uom,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              );
              if (narrow) {
                return Column(
                  children: [
                    qtyField,
                    const SizedBox(height: 12),
                    uomField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: qtyField),
                  const SizedBox(width: 10),
                  Expanded(child: uomField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ItemRow {
  String? itemCode;
  String itemName;
  String? sourceWarehouse;
  String uom;
  final TextEditingController qtyCtrl;

  _ItemRow({
    this.itemCode,
    this.itemName = '',
    this.sourceWarehouse,
    this.uom = '',
    String qtyText = '1',
  }) : qtyCtrl = TextEditingController(text: qtyText);

  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0;

  void dispose() => qtyCtrl.dispose();
}
