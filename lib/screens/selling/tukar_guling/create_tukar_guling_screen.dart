import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/tukar_guling.dart';
import '../../../state/selling/tukar_guling_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../shared/sales_attachment_card.dart';
import '../shared/sales_ui.dart';

class CreateTukarGulingScreen extends StatefulWidget {
  final String? existingName;
  final String? initialCompany;

  const CreateTukarGulingScreen({
    super.key,
    this.existingName,
    this.initialCompany,
  });

  @override
  State<CreateTukarGulingScreen> createState() =>
      _CreateTukarGulingScreenState();
}

class _CreateTukarGulingScreenState extends State<CreateTukarGulingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keteranganCtrl = TextEditingController();
  final _rows = <_ItemRow>[];
  final _imagePicker = ImagePicker();
  final _photos = <XFile>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _series;
  List<String> _seriesOptions = const [];
  String? _company;
  String? _customer;
  String _customerName = '';
  String _jenis = '';
  String _metode = '';
  bool _jenisLocked = false;
  String _pullSummary = '';
  DateTime _postingDate = DateTime.now();
  String? _stockEntry;
  String? _savedName;
  final _customerNames = <String, String>{};
  final _claims = <_ClaimRow>[];
  final _itemMeta = <String, ({String name, String uom})>{};
  List<String> _existingAttachmentNames = const [];

  bool get _isEdit =>
      (widget.existingName ?? '').trim().isNotEmpty ||
      (_savedName ?? '').trim().isNotEmpty;

  bool get _isFinal => _jenis.toLowerCase() == 'final';
  bool get _isHarian => _jenis.toLowerCase() == 'harian';
  bool get _isGetFrom => _isFinal && _metode == 'Get From Harian';
  bool get _isManual => _isFinal && _metode == 'Input Langsung';

  String? get _documentName {
    final existing = widget.existingName?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    final saved = _savedName?.trim() ?? '';
    return saved.isEmpty ? null : saved;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keteranganCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    for (final claim in _claims) {
      claim.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<TukarGulingState>();
      final companies = state.sellingCompanies;
      final fromList = widget.initialCompany?.trim() ?? '';
      _company ??= fromList.isNotEmpty &&
              (companies.isEmpty || companies.contains(fromList))
          ? fromList
          : state.preferredCompany(companies) ??
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

  Future<void> _applyExisting(TukarGulingState state, String name) async {
    final meta = await state.resolveMeta();
    final doc = await state.fetchDetail(name);
    _series = doc['naming_series']?.toString().trim() ?? _series;
    _company = doc['company']?.toString().trim() ?? _company;
    _customer = doc['customer']?.toString().trim() ?? _customer;
    _customerName = doc[meta.customerNameField]?.toString().trim() ??
        doc['customer_name']?.toString().trim() ??
        '';
    final jenis = doc[meta.jenisField]?.toString().trim() ??
        doc['jenis_input']?.toString().trim() ??
        '';
    _jenis = jenis;
    _jenisLocked = true;
    _metode = doc[meta.metodeField]?.toString().trim() ??
        doc['custom_metode_final']?.toString().trim() ??
        '';
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
    final rawClaims = state.claimRowsOf(doc);
    for (final claim in _claims) {
      claim.dispose();
    }
    _claims
      ..clear()
      ..addAll([
        for (final raw in rawClaims)
            _ClaimRow(
              claimDate: DateTime.tryParse(_claimDateText(raw)) ?? _postingDate,
              itemCode: _claimItemCode(raw),
              itemName: _claimItemName(raw),
              keterangan: _claimNote(raw),
              sourceName: meta.claimSourceField.isEmpty
                  ? ''
                  : raw[meta.claimSourceField]?.toString() ?? '',
              qtyText: _qtyText(_claimQty(raw)),
            ),
      ]);
    final rawItems = state.itemRowsOf(doc);
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        for (final raw in rawItems)
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
    final hasItems = _rows.any((row) => (row.itemCode ?? '').isNotEmpty);
    final hasClaims = _claims.any((row) => (row.itemCode ?? '').isNotEmpty);
    if (jenis.isEmpty && (hasItems || hasClaims)) _jenis = 'Final';
    if (_isFinal && _metode.isEmpty) {
      if (hasClaims) {
        _metode = 'Get From Harian';
      } else if (hasItems) {
        _metode = 'Input Langsung';
      }
    }
    if (_isHarian && _claims.isEmpty) _claims.add(_ClaimRow());
    if (_isManual && _rows.isEmpty) _rows.add(_manualRow());
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
    final rows = await context.read<TukarGulingState>().searchCustomers(
      query: query,
    );
    for (final row in rows) {
      final id = row['name']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      _customerNames[id] = row['customer_name']?.toString().trim() ?? '';
    }
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
        await context.read<TukarGulingState>().searchItems(query: query);
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
    final rows = await context.read<TukarGulingState>().searchWarehouses(
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

  Future<int> _uploadPhotos(TukarGulingState state, String name) async {
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
    if (!_jenisLocked) {
      setState(() => _error = 'Pilih Harian atau Final.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final filledClaims = _claims
        .where((row) => (row.itemCode ?? '').trim().isNotEmpty)
        .toList();
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
    if (_isHarian) {
      if (filledClaims.isEmpty) {
        setState(() => _error = 'Tambahkan minimal satu klaim dalam kg.');
        return;
      }
      for (var i = 0; i < filledClaims.length; i++) {
        if (filledClaims[i].qtyKg <= 0) {
          setState(() => _error = 'Klaim ${i + 1}: Qty kg harus lebih dari 0.');
          return;
        }
      }
    } else if (_isFinal) {
      if (!_isGetFrom && !_isManual) {
        setState(() => _error = 'Pilih metode Final.');
        return;
      }
      if (_isGetFrom && filledClaims.isEmpty) {
        setState(() => _error = 'Tarik klaim Harian dulu.');
        return;
      }
      if (_isManual && filledClaims.isNotEmpty) {
        setState(
          () => _error = 'Input Langsung tidak boleh memiliki Klaim Harian.',
        );
        return;
      }
      if (filled.isEmpty) {
        setState(
          () => _error = _isManual
              ? 'Tambahkan minimal satu item box.'
              : 'Kg yang ditarik belum cukup untuk 1 box.',
        );
        return;
      }
      for (var i = 0; i < filled.length; i++) {
        final row = filled[i];
        if ((row.sourceWarehouse ?? '').trim().isEmpty) {
          setState(() => _error = 'Item ${i + 1}: Source Warehouse wajib.');
          return;
        }
        if (row.qty <= 0) {
          setState(() => _error = 'Item ${i + 1}: Qty box harus lebih dari 0.');
          return;
        }
      }
    } else if (filled.isEmpty) {
      setState(() => _error = 'Tambahkan minimal satu item.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = TukarGulingDraft(
        namingSeries: _series,
        postingDate: _postingDate,
        company: _company!.trim(),
        customer: _customer!.trim(),
        customerName: _customerName,
        jenisInput: _isFinal ? 'Final' : 'Harian',
        metodeFinal: _isFinal ? _metode : '',
        keterangan: _isFinal ? '' : _keteranganCtrl.text,
        claims: [
          if (!_isManual)
          for (final claim in filledClaims)
            TukarGulingClaimDraft(
              claimDate: claim.claimDate,
              itemCode: claim.itemCode!,
              itemName: claim.itemName,
              qtyKg: claim.qtyKg,
              keterangan: claim.keteranganCtrl.text,
              sourceName: claim.sourceName,
            ),
        ],
        items: [
          for (final row in filled)
            TukarGulingItemDraft(
              itemCode: row.itemCode!,
              itemName: row.itemName,
              sourceWarehouse: row.sourceWarehouse!,
              qty: row.qty,
              uom: row.uom,
            ),
        ],
      );
      final state = context.read<TukarGulingState>();
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
                ? 'Tukar Guling $savedName berhasil $savedLabel, tetapi $failedUploads foto gagal diunggah.'
                : 'Tukar Guling $savedName berhasil $savedLabel.',
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
    final state = context.watch<TukarGulingState>();
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
          _isEdit ? 'Edit Tukar Guling' : 'Buat Tukar Guling',
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
                        onSelected: (value) => setState(() {
                          _customer = value;
                          _customerName = value == null
                              ? ''
                              : (_customerNames[value] ?? '');
                          if (_isFinal) {
                            _pullSummary = '';
                            for (final claim in _claims) {
                              claim.dispose();
                            }
                            _claims.clear();
                            for (final row in _rows) {
                              row.dispose();
                            }
                            _rows.clear();
                          }
                        }),
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
                      if (_jenisLocked)
                        InputDecorator(
                          decoration: _decoration('Jenis'),
                          child: Text(
                            _isFinal ? 'Final' : 'Harian',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _chooseJenis('Harian'),
                                child: const Text('Harian'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _chooseJenis('Final'),
                                child: const Text('Final'),
                              ),
                            ),
                          ],
                        ),
                      if (_isFinal) ...[
                        const SizedBox(height: 14),
                        _methodPicker(),
                      ],
                      if (!_isFinal && (_stockEntry ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: _decoration('Stock Entry'),
                          child: Text(
                            _stockEntry!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_jenisLocked) ...[
                  const SizedBox(height: 12),
                  if (_isGetFrom) ...[
                    _section(
                      title: 'Klaim Harian',
                      children: [
                        const Text(
                          'Tarik beberapa transaksi Harian. Qty tetap kg, lalu dikonversi ke box.',
                          style: TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _openDailyClaims,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Tarik Tukar Guling Harian'),
                        ),
                        if (_pullSummary.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F6EE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _pullSummary,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                        for (var i = 0; i < _claims.length; i++) ...[
                          const SizedBox(height: 8),
                          _pulledClaimTile(i),
                        ],
                      ],
                    ),
                    if (_rows.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _section(
                        title: 'Tukar Guling Item',
                        children: [
                          for (var i = 0; i < _rows.length; i++) ...[
                            _itemCard(i),
                            if (i != _rows.length - 1) const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ],
                  ] else if (_isManual)
                    _section(
                      title: 'Tukar Guling Item',
                      children: [
                        const Text(
                          'Isi item dan qty box.',
                          style: TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (var i = 0; i < _rows.length; i++) ...[
                          const SizedBox(height: 12),
                          _itemCard(i),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _rows.add(_manualRow())),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add Row'),
                        ),
                      ],
                    )
                  else if (_isHarian)
                    _section(
                      title: 'Klaim Harian',
                      children: [
                        const Text(
                          'Isi tanggal, item, dan qty kg.',
                          style: TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (var i = 0; i < _claims.length; i++) ...[
                          const SizedBox(height: 12),
                          _claimCard(i),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => setState(
                            () => _claims.add(_ClaimRow(claimDate: _postingDate)),
                          ),
                          icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Row'),
                      ),
                    ],
                    ),
                  ],
                  if (_jenisLocked) ...[
                  const SizedBox(height: 12),
                  SalesAttachmentCard(
                    title: 'Attachment',
                    existingNames: _existingAttachmentNames,
                    photos: _photos,
                    onCamera: _saving ? null : _pickCamera,
                    onGallery: _saving ? null : _pickGallery,
                    onRemove: (index) => setState(() => _photos.removeAt(index)),
                  ),
                  if (!_isFinal) ...[
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
                  ],
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

  _ItemRow _manualRow() {
    return _ItemRow(
      uom: 'Box',
      sourceWarehouse: context.read<TukarGulingState>().preferredWarehouseName(
        _company,
      ),
    );
  }

  void _chooseMetode(String metode) {
    final hasData = _claims.any((row) => (row.itemCode ?? '').isNotEmpty) ||
        _rows.any((row) => (row.itemCode ?? '').isNotEmpty);
    if (_metode.isNotEmpty && _metode != metode && hasData) {
      setState(() {
        _error =
            'Tabel sudah memiliki data. Kosongkan baris atau buat dokumen baru.';
      });
      return;
    }
    setState(() {
      _metode = metode;
      _error = null;
      _pullSummary = '';
      if (metode == 'Input Langsung') {
        for (final claim in _claims) {
          claim.dispose();
        }
        _claims.clear();
        if (_rows.isEmpty) _rows.add(_manualRow());
      }
    });
  }

  Widget _methodPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Metode Final',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _methodCard(
                title: 'Get From Harian',
                subtitle: 'Gabungkan klaim dalam kg dan konversi menjadi box.',
                selected: _isGetFrom,
                onTap: () => _chooseMetode('Get From Harian'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _methodCard(
                title: 'Input Langsung',
                subtitle: 'Isi item dan qty box.',
                selected: _isManual,
                onTap: () => _chooseMetode('Input Langsung'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Pilih salah satu metode untuk melanjutkan.',
          style: TextStyle(
            color: AppColors.slate,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _methodCard({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFFE8F6EE) : AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF08743D) : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 18,
                    color: selected ? const Color(0xFF08743D) : AppColors.slate,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _chooseJenis(String jenis) {
    setState(() {
      _jenis = jenis;
      _jenisLocked = true;
      _pullSummary = '';
      if (_isHarian && _claims.isEmpty) {
        _claims.add(_ClaimRow(claimDate: _postingDate));
      }
    });
  }

  Future<void> _openDailyClaims() async {
    final customer = _customer?.trim() ?? '';
    if (customer.isEmpty) {
      setState(() => _error = 'Pilih customer dulu.');
      return;
    }
    if (_claims.isNotEmpty ||
        _rows.any((row) => (row.itemCode ?? '').trim().isNotEmpty)) {
      setState(() => _error = 'Draft Final sudah memiliki data.');
      return;
    }
    final state = context.read<TukarGulingState>();
    List<TukarGulingDailyClaim> claims;
    try {
      claims = await state.fetchDailyClaims(
        customer: customer,
        company: _company,
        excludeName: _documentName,
        postingDate: _postingDate,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
      return;
    }
    if (!mounted) return;
    claims = claims.where((claim) => claim.itemCode.isNotEmpty).toList();
    if (claims.isEmpty) {
      setState(
        () => _error = 'Belum ada klaim Harian dalam kg untuk customer ini.',
      );
      return;
    }
    final selected = await showModalBottomSheet<List<TukarGulingDailyClaim>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DailyClaimSheet(state: state, claims: claims),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _applyPulledClaims(state, selected);
  }

  Future<void> _applyPulledClaims(
    TukarGulingState state,
    List<TukarGulingDailyClaim> selected,
  ) async {
    final ordered = [...selected]..sort((a, b) {
        final byDate = a.claimDate.compareTo(b.claimDate);
        if (byDate != 0) return byDate;
        return a.sourceName.compareTo(b.sourceName);
      });
    final grouped = <String, ({String name, double kg, List<TukarGulingDailyClaim> rows})>{};
    for (final claim in ordered) {
      final current = grouped[claim.itemCode];
      grouped[claim.itemCode] = (
        name: claim.itemName.isNotEmpty
            ? claim.itemName
            : (current?.name ?? claim.itemCode),
        kg: (current?.kg ?? 0) + claim.qtyKg,
        rows: [...?current?.rows, claim],
      );
    }
    final summaries = <String>[];
    final nextRows = <_ItemRow>[];
    final allocated = <TukarGulingDailyClaim>[];
    final warehouse = state.preferredWarehouseName(_company) ?? '';
    for (final entry in grouped.entries) {
      final perBox = await state.kgPerBox(entry.key);
      if (perBox == null || perBox <= 0) {
        if (!mounted) return;
        setState(() {
          _error =
              '${entry.value.name}: konversi Kg/Box belum ada untuk item group ini.';
        });
        return;
      }
      final boxes = ((entry.value.kg + 0.000001) / perBox).floor();
      var needed = _round3(boxes * perBox);
      final remainder = _round3(entry.value.kg - needed);
      summaries.add(
        '${entry.value.name}: ${_qtyText(entry.value.kg)} kg = $boxes box'
        '${remainder > 0.001 ? ', sisa ${_qtyText(remainder)} kg' : ''}',
      );
      if (boxes <= 0) continue;
      for (final claim in entry.value.rows) {
        if (needed <= 0) break;
        final used = _round3(claim.qtyKg < needed ? claim.qtyKg : needed);
        if (used <= 0) continue;
        allocated.add(
          TukarGulingDailyClaim(
            sourceName: claim.sourceName,
            claimDate: claim.claimDate,
            itemCode: claim.itemCode,
            itemName: entry.value.name,
            qtyKg: used,
            keterangan: claim.keterangan,
          ),
        );
        needed = _round3(needed - used);
      }
      nextRows.add(
        _ItemRow(
          itemCode: entry.key,
          itemName: entry.value.name,
          sourceWarehouse: warehouse,
          uom: 'Box',
          qtyText: boxes.toString(),
        ),
      );
    }
    if (nextRows.isEmpty) {
      if (!mounted) return;
      setState(
        () => _error = 'Total kg belum cukup untuk 1 box. Kumpulkan klaim lagi.',
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = null;
      _pullSummary = summaries.join('\n');
      for (final claim in _claims) {
        claim.dispose();
      }
      _claims
        ..clear()
        ..addAll([
          for (final claim in allocated)
            _ClaimRow(
              claimDate: claim.claimDate,
              itemCode: claim.itemCode,
              itemName: claim.itemName,
              keterangan: claim.keterangan,
              sourceName: claim.sourceName,
              qtyText: _qtyText(claim.qtyKg),
              locked: true,
            ),
        ]);
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll(nextRows);
    });
  }

  Widget _pulledClaimTile(int index) {
    final claim = _claims[index];
    final code = claim.itemCode ?? '';
    final item = claim.itemName.isEmpty || claim.itemName == code
        ? code
        : claim.itemName;
    final note = claim.keteranganCtrl.text.trim();
    final date = DateFormat('dd-MM-yyyy').format(claim.claimDate);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  claim.sourceName.isEmpty ? 'Klaim ${index + 1}' : claim.sourceName,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · $item',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_qtyText(claim.qtyKg)} kg',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _claimCard(int index, {bool readOnly = false}) {
    final claim = _claims[index];
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
              Expanded(
                child: Text(
                  claim.sourceName.isEmpty
                      ? 'Klaim ${index + 1}'
                      : claim.sourceName,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!readOnly && _claims.length > 1)
                IconButton(
                  tooltip: 'Hapus baris',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _claims.removeAt(index).dispose()),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: readOnly
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: claim.claimDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked == null || !mounted) return;
                          setState(() => claim.claimDate = picked);
                        },
                  child: InputDecorator(
                    decoration: _decoration('Tanggal'),
                    child: Text(DateFormat('dd-MM-yyyy').format(claim.claimDate)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: claim.qtyCtrl,
                  readOnly: readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _decoration('Qty (kg) *'),
                  validator: (value) {
                    if ((claim.itemCode ?? '').isEmpty) return null;
                    return claim.qtyKg <= 0 ? 'Qty kg > 0' : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (readOnly)
            InputDecorator(
              decoration: _decoration('Item'),
              child: Text(
                claim.itemName.isEmpty
                    ? (claim.itemCode ?? '-')
                    : '${claim.itemName} (${claim.itemCode})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else
            ErpItemAutocompleteField(
              label: 'Item *',
              selectedId: claim.itemCode,
              decoration: _decoration('Item *'),
              options: [
                if ((claim.itemCode ?? '').isNotEmpty)
                  ErpItemOption(
                    id: claim.itemCode!,
                    label: claim.itemName.isEmpty
                        ? claim.itemCode!
                        : '${claim.itemName} (${claim.itemCode})',
                  ),
              ],
              onSearch: _searchItems,
              onSelected: (value) async {
                if (value == null) {
                  setState(() {
                    claim.itemCode = null;
                    claim.itemName = '';
                  });
                  return;
                }
                if (!_itemMeta.containsKey(value)) await _searchItems(value);
                setState(() {
                  claim.itemCode = value;
                  claim.itemName = _itemMeta[value]?.name ?? '';
                });
              },
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: claim.keteranganCtrl,
            readOnly: readOnly,
            decoration: _decoration('Keterangan'),
          ),
        ],
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
                  row.uom = _isManual ? 'Box' : '';
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
                row.uom = _isManual ? 'Box' : (meta?.uom ?? row.uom);
                if (_isManual && (row.sourceWarehouse ?? '').isEmpty) {
                  row.sourceWarehouse = context
                      .read<TukarGulingState>()
                      .preferredWarehouseName(_company);
                }
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
                decoration: _decoration(_isManual ? 'Qty (Box) *' : 'Qty *'),
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

  double get qty =>
      double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;

  void dispose() => qtyCtrl.dispose();
}

class _ClaimRow {
  DateTime claimDate;
  String? itemCode;
  String itemName;
  String sourceName;
  final bool locked;
  final TextEditingController qtyCtrl;
  final TextEditingController keteranganCtrl;

  _ClaimRow({
    DateTime? claimDate,
    this.itemCode,
    this.itemName = '',
    this.sourceName = '',
    String keterangan = '',
    this.locked = false,
    String qtyText = '',
  }) : claimDate = claimDate ?? DateTime.now(),
       qtyCtrl = TextEditingController(text: qtyText),
       keteranganCtrl = TextEditingController(text: keterangan);

  double get qtyKg =>
      double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;

  void dispose() {
    qtyCtrl.dispose();
    keteranganCtrl.dispose();
  }
}

String _claimItemCode(Map map) {
  for (final key in ['item_code', 'item']) {
    final text = map[key]?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return _mapText(
    map,
    (key) =>
        key.contains('item') && !key.contains('name') && !key.contains('group'),
  );
}

String _claimItemName(Map map) {
  final named = map['item_name']?.toString().trim() ?? '';
  if (named.isNotEmpty && named != 'null') return named;
  return _mapText(map, (key) => key.contains('item') && key.contains('name'));
}

String _claimNote(Map map) {
  final note = map['keterangan']?.toString().trim() ?? '';
  if (note.isNotEmpty && note != 'null') return note;
  return _mapText(map, (key) => key.contains('keterangan') || key == 'note');
}

String _claimDateText(Map map) {
  for (final key in ['tanggal_klaim', 'claim_date', 'posting_date']) {
    final text = map[key]?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return _mapText(map, (key) => key.contains('tanggal') || key.endsWith('_date'));
}

Object? _claimQty(Map map) {
  Object? fallback;
  for (final entry in map.entries) {
    final key = entry.key.toString().toLowerCase();
    if (!key.contains('qty')) continue;
    if (key.contains('kg')) return entry.value;
    fallback ??= entry.value;
  }
  return fallback;
}

String _mapText(Map map, bool Function(String key) match) {
  for (final entry in map.entries) {
    final key = entry.key.toString().toLowerCase();
    if (!match(key)) continue;
    final text = entry.value?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

double _round3(double value) => (value * 1000).roundToDouble() / 1000;

String _qtyText(Object? raw) {
  final qty = double.tryParse(raw?.toString().replaceAll(',', '.') ?? '') ?? 0;
  return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}

class _DailyClaimSheet extends StatefulWidget {
  final TukarGulingState state;
  final List<TukarGulingDailyClaim> claims;

  const _DailyClaimSheet({required this.state, required this.claims});

  @override
  State<_DailyClaimSheet> createState() => _DailyClaimSheetState();
}

class _DailyClaimSheetState extends State<_DailyClaimSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.claims.length; i++) i,
  };
  final _perBox = <String, double?>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFactors();
  }

  Future<void> _loadFactors() async {
    final codes = widget.claims.map((claim) => claim.itemCode).toSet();
    for (final code in codes) {
      try {
        _perBox[code] = await widget.state.kgPerBox(code);
      } catch (_) {
        _perBox[code] = null;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final selected = [
      for (final index in _selected) widget.claims[index],
    ];
    final grouped = <String, ({String name, double kg})>{};
    for (final claim in selected) {
      final current = grouped[claim.itemCode];
      grouped[claim.itemCode] = (
        name: claim.itemName.isEmpty ? claim.itemCode : claim.itemName,
        kg: (current?.kg ?? 0) + claim.qtyKg,
      );
    }
    var totalKg = 0.0;
    var totalBox = 0;
    for (final entry in grouped.entries) {
      totalKg += entry.value.kg;
      final perBox = _perBox[entry.key];
      if (perBox != null && perBox > 0) {
        totalBox += (entry.value.kg / perBox).floor();
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tukar Guling Harian',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pilih klaim. Qty masih kg, konversi ke box ditampilkan di bawah.',
              style: TextStyle(color: AppColors.slate, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < widget.claims.length; i++)
                    CheckboxListTile(
                      value: _selected.contains(i),
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.claims[i].sourceName),
                      subtitle: Text(
                        '${DateFormat('dd-MM-yyyy').format(widget.claims[i].claimDate)}'
                        ' · ${widget.claims[i].itemName.isEmpty ? widget.claims[i].itemCode : widget.claims[i].itemName}'
                        ' · ${_qtyText(widget.claims[i].qtyKg)} kg',
                      ),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _loading
                  ? 'Menghitung konversi...'
                  : 'Total ${_qtyText(totalKg)} kg → $totalBox box',
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _selected.isEmpty || _loading
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Tarik ke Tukar Guling Final'),
            ),
          ],
        ),
      ),
    );
  }
}
