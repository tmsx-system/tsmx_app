import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/delivery_return.dart';
import '../../../state/selling/delivery_return_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../shared/sales_attachment_card.dart';
import '../shared/sales_ui.dart';

class CreateDeliveryReturnScreen extends StatefulWidget {
  final String? existingName;

  const CreateDeliveryReturnScreen({super.key, this.existingName});

  @override
  State<CreateDeliveryReturnScreen> createState() =>
      _CreateDeliveryReturnScreenState();
}

class _CreateDeliveryReturnScreenState extends State<CreateDeliveryReturnScreen> {
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
  String _customerName = '';
  String? _deliveryNote;
  DateTime _postingDate = DateTime.now();
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
      final state = context.read<DeliveryReturnState>();
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

  Future<void> _applyExisting(DeliveryReturnState state, String name) async {
    final doc = await state.fetchDetail(name);
    _loadedDocument = doc;
    _series = doc['naming_series']?.toString().trim() ?? _series;
    _company = doc['company']?.toString().trim() ?? _company;
    _customer = doc['customer']?.toString().trim() ?? _customer;
    _customerName = doc['customer_name']?.toString().trim() ?? _customerName;
    _deliveryNote = doc['delivery_asal']?.toString().trim() ??
        doc['delivery_note']?.toString().trim() ??
        _deliveryNote;
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
        doc['return_detail'] ?? doc['items'] ?? doc['delivery_return_detail'];
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
              uom: raw['uom']?.toString() ?? '',
              qtyDnText: _qtyText(raw['qty_dn']),
              qtyTolakText: _qtyText(raw['qty_tolak']),
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
    final rows = await context.read<DeliveryReturnState>().searchCustomers(
      query: query,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').isNotEmpty)
          () {
            final id = row['name'].toString();
            final name = row['customer_name']?.toString().trim() ?? '';
            if (name.isNotEmpty) _customerNames[id] = name;
            return ErpItemOption(
              id: id,
              label: name.isNotEmpty ? '$name ($id)' : id,
            );
          }(),
    ];
  }

  final _customerNames = <String, String>{};

  Future<void> _selectCustomer(String? value) async {
    setState(() {
      _customer = value;
      _customerName = value == null ? '' : (_customerNames[value] ?? '');
      _deliveryNote = null;
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..add(_ItemRow());
    });
    if (value == null || _customerName.isNotEmpty) return;
    final rows = await context.read<DeliveryReturnState>().searchCustomers(
      query: value,
    );
    if (!mounted || _customer != value) return;
    for (final row in rows) {
      if (row['name']?.toString() == value) {
        setState(() {
          _customerName = row['customer_name']?.toString().trim() ?? '';
        });
        break;
      }
    }
  }

  Future<List<ErpItemOption>> _searchDeliveryNotes(String query) async {
    final customer = _customer?.trim() ?? '';
    if (customer.isEmpty) return const [];
    final rows = await context.read<DeliveryReturnState>().searchDeliveryNotes(
      customer: customer,
      company: _company,
      query: query,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString(),
            label: () {
              final date = row['posting_date']?.toString().trim() ?? '';
              final id = row['name'].toString();
              return date.isEmpty ? id : '$id • $date';
            }(),
          ),
    ];
  }

  Future<void> _selectDeliveryNote(String? value) async {
    setState(() => _deliveryNote = value);
    if (value == null || value.trim().isEmpty) return;
    try {
      final items = await context
          .read<DeliveryReturnState>()
          .itemsFromDeliveryNote(value);
      if (!mounted || _deliveryNote != value) return;
      setState(() {
        for (final row in _rows) {
          row.dispose();
        }
        _rows
          ..clear()
          ..addAll([
            for (final item in items)
              _ItemRow(
                itemCode: item.itemCode,
                itemName: item.itemName,
                uom: item.uom,
                qtyDnText: _qtyText(item.qtyDn),
                qtyTolakText: '0',
              ),
          ]);
        if (_rows.isEmpty) _rows.add(_ItemRow());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    }
  }

  Future<List<ErpItemOption>> _searchItems(String query) async {
    final rows =
        await context.read<DeliveryReturnState>().searchItems(query: query);
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

  Future<int> _uploadPhotos(DeliveryReturnState state, String name) async {
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
      if (row.qtyDn < 0 || row.qtyTolak <= 0) {
        setState(
          () => _error = 'Item ${i + 1}: Qty DN dan Qty Tolak harus valid.',
        );
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = DeliveryReturnDraft(
        namingSeries: _series,
        postingDate: _postingDate,
        company: _company!.trim(),
        customer: _customer!.trim(),
        customerName: _customerName,
        deliveryNote: _deliveryNote?.trim() ?? '',
        keterangan: _keteranganCtrl.text,
        items: [
          for (final row in filled)
            DeliveryReturnItemDraft(
              itemCode: row.itemCode!,
              itemName: row.itemName,
              qtyDn: row.qtyDn,
              qtyTolak: row.qtyTolak,
              uom: row.uom,
            ),
        ],
      );
      final state = context.read<DeliveryReturnState>();
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
        setState(() => _savedName = name);
      }
      final failedUploads = await _uploadPhotos(state, savedName);
      if (!mounted) return;
      final savedLabel = createdNew ? 'dibuat' : 'diperbarui';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedUploads > 0
                ? 'Delivery Return $savedName berhasil $savedLabel, tetapi $failedUploads foto gagal diunggah.'
                : 'Delivery Return $savedName berhasil $savedLabel.',
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
    final rejectState = context.read<DeliveryReturnState>();
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
    final state = context.watch<DeliveryReturnState>();
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
          _isEdit ? 'Edit Delivery Return' : 'Buat Delivery Return',
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
                        onSelected: (value) => setState(() => _company = value),
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
                        onSelected: (value) => _selectCustomer(value),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Customer wajib'
                                : null,
                      ),
                      if (_customerName.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: _decoration('Customer Name'),
                          child: Text(
                            _customerName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ErpItemAutocompleteField(
                        key: ValueKey(
                          'dn-${_customer ?? ''}-${_deliveryNote ?? ''}',
                        ),
                        label: 'Delivery Note',
                        selectedId: _deliveryNote,
                        decoration: _decoration(
                          'Delivery Note',
                          hint: (_customer ?? '').isEmpty
                              ? 'Pilih customer dulu'
                              : 'Delivery Note milik customer',
                        ),
                        options: [
                          if ((_deliveryNote ?? '').isNotEmpty)
                            ErpItemOption(
                              id: _deliveryNote!,
                              label: _deliveryNote!,
                            ),
                        ],
                        onSearch: (_customer ?? '').isEmpty
                            ? null
                            : _searchDeliveryNotes,
                        onSelected: (value) => _selectDeliveryNote(value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Return Detail',
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
                  _section(
                    title: 'Keterangan',
                    children: [
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
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 340;
              final qtyDnField = TextFormField(
                controller: row.qtyDnCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('Qty DN'),
                validator: (value) {
                  if ((row.itemCode ?? '').isEmpty) return null;
                  final qty = double.tryParse(value?.trim() ?? '');
                  return qty == null || qty < 0 ? 'Qty DN tidak valid' : null;
                },
              );
              final qtyTolakField = TextFormField(
                controller: row.qtyTolakCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('Qty Tolak *'),
                validator: (value) {
                  if ((row.itemCode ?? '').isEmpty) return null;
                  final qty = double.tryParse(value?.trim() ?? '');
                  return qty == null || qty <= 0 ? 'Qty Tolak > 0' : null;
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
                    qtyDnField,
                    const SizedBox(height: 12),
                    qtyTolakField,
                    const SizedBox(height: 12),
                    uomField,
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: qtyDnField),
                      const SizedBox(width: 10),
                      Expanded(child: qtyTolakField),
                    ],
                  ),
                  const SizedBox(height: 12),
                  uomField,
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
  String uom;
  final TextEditingController qtyDnCtrl;
  final TextEditingController qtyTolakCtrl;

  _ItemRow({
    this.itemCode,
    this.itemName = '',
    this.uom = '',
    String qtyDnText = '0',
    String qtyTolakText = '1',
  }) : qtyDnCtrl = TextEditingController(text: qtyDnText),
       qtyTolakCtrl = TextEditingController(text: qtyTolakText);

  double get qtyDn => double.tryParse(qtyDnCtrl.text.trim()) ?? 0;
  double get qtyTolak => double.tryParse(qtyTolakCtrl.text.trim()) ?? 0;

  void dispose() {
    qtyDnCtrl.dispose();
    qtyTolakCtrl.dispose();
  }
}

String _qtyText(Object? raw) {
  final qty = double.tryParse(raw?.toString() ?? '') ?? 0;
  return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}
