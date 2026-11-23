import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_opname.dart';
import '../../../../../models/warehouse_info.dart';
import '../../../../../state/warehouse/stock_opname_state.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/erp_error_message.dart';
import '../../../../../widgets/erp/erp_item_autocomplete_field.dart';
import 'stock_opname_widgets.dart';

class CreateStockOpnameScreen extends StatefulWidget {
  final String? company;
  final String? existingName;

  const CreateStockOpnameScreen({super.key, this.company, this.existingName});

  @override
  State<CreateStockOpnameScreen> createState() =>
      _CreateStockOpnameScreenState();
}

class _CreateStockOpnameScreenState extends State<CreateStockOpnameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lines = <_OpnameLine>[];
  final _dateFormat = DateFormat('yyyy-MM-dd');
  List<WarehouseInfo> _warehouses = const [];
  List<String> _seriesOptions = const [];
  List<ErpItemOption> _groupOptions = const [];
  String? _company;
  String? _series;
  String? _warehouse;
  String? _itemGroup;
  DateTime _postingDate = DateTime.now();
  TimeOfDay _postingTime = TimeOfDay.now();
  bool _loading = true;
  bool _saving = false;
  bool _busy = false;
  String? _busyText;
  String? _error;
  bool _applying = false;

  StockOpnameState get _api =>
      StockOpnameState(context.read<WarehouseStockState>().appState);

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
    final stock = context.read<WarehouseStockState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await stock.ensureWarehousesLoaded(
        forceRefresh: stock.warehouses.isEmpty,
      );
      final series = await _api.fetchNamingSeries();
      final groups = await _api.searchItemGroups('');
      if (!mounted) return;
      setState(() {
        _warehouses = _leafWarehouses(stock.warehouses);
        _seriesOptions = series;
        _series ??= series.isEmpty ? null : series.first;
        _groupOptions = [
          for (final name in groups) ErpItemOption(id: name, label: name),
        ];
        _company ??= stock.preferredCompany(
          stock.stockCompanies.map((entry) => entry.key),
        );
      });
      final existing = widget.existingName?.trim() ?? '';
      if (existing.isNotEmpty) await _loadExisting(existing);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = captureErpError(
          context,
          error,
          action: 'memuat form Stock Opname',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<WarehouseInfo> _leafWarehouses(List<WarehouseInfo> rows) {
    return rows.where((row) => !row.isGroup && row.isDisabled != true).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<WarehouseInfo> get _companyWarehouses {
    final company = _company?.trim() ?? '';
    if (company.isEmpty) return _warehouses;
    return _warehouses.where((row) => row.company == company).toList();
  }

  Future<void> _loadExisting(String name) async {
    final doc = await _api.fetchDetail(name);
    if (!mounted) return;
    _applying = true;
    final parsedDate = DateTime.tryParse(doc['posting_date']?.toString() ?? '');
    setState(() {
      _company = doc['company']?.toString();
      _warehouse = doc['warehouse']?.toString();
      _itemGroup = doc['item_group']?.toString();
      _series = doc['naming_series']?.toString();
      if (parsedDate != null) _postingDate = parsedDate;
      _postingTime = _parseTime(doc['posting_time']?.toString() ?? '');
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..addAll([
          for (final row in _api.linesOf(doc)) _OpnameLine.fromLine(row),
        ]);
      if ((_itemGroup ?? '').isNotEmpty &&
          _groupOptions.every((option) => option.id != _itemGroup)) {
        _groupOptions = [
          ErpItemOption(id: _itemGroup!, label: _itemGroup!),
          ..._groupOptions,
        ];
      }
    });
    _applying = false;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _postingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _postingDate = picked);
    await _refreshStockIfNeeded();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _postingTime,
    );
    if (picked == null || !mounted) return;
    setState(() => _postingTime = picked);
    await _refreshStockIfNeeded();
  }

  Future<void> _onCompany(String? value) async {
    final warehouse = _warehouse;
    final stillValid =
        warehouse != null &&
        _leafWarehouses(
          context.read<WarehouseStockState>().warehouses,
        ).any((row) => row.name == warehouse && row.company == value);
    setState(() {
      _company = value;
      if (!stillValid) _warehouse = null;
    });
    if (stillValid) await _refreshStockIfNeeded();
  }

  Future<void> _onWarehouse(String? value) async {
    setState(() => _warehouse = value);
    await _refreshStockIfNeeded();
  }

  Future<void> _onItemGroup(String? value) async {
    setState(() => _itemGroup = value);
    if (_applying || value == null || value.isEmpty) return;
    if ((widget.existingName ?? '').trim().isNotEmpty && _lines.isNotEmpty) {
      return;
    }
    await _pickSkus();
  }

  Future<void> _refreshStockIfNeeded() async {
    if (_applying || _busy) return;
    if (_lines.any((line) => line.itemCode.isNotEmpty)) {
      await _refreshStock();
    }
  }

  String? _headerError() {
    if ((_company ?? '').trim().isEmpty) return 'Isi Company terlebih dahulu.';
    if ((_warehouse ?? '').trim().isEmpty) {
      return 'Isi Warehouse terlebih dahulu.';
    }
    if ((_itemGroup ?? '').trim().isEmpty) {
      return 'Isi Item Group terlebih dahulu.';
    }
    return null;
  }

  Future<void> _pickSkus() async {
    final header = _headerError();
    if (header != null) {
      setState(() => _error = header);
      return;
    }
    final group = _itemGroup!.trim();
    setState(() {
      _busy = true;
      _busyText = 'Mencari SKU...';
      _error = null;
    });
    List<StockOpnameItemChoice> items;
    try {
      final groups = await _api.itemGroupsUnder(group);
      if (!mounted || _itemGroup != group) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
        return;
      }
      items = await _api.itemsInGroups(groups);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = captureErpError(context, error, action: 'memuat SKU');
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyText = null;
    });
    if (_itemGroup != group) return;
    if (items.isEmpty) {
      setState(
        () => _error = 'Tidak ada SKU aktif pada Item Group $group.',
      );
      return;
    }
    final selected = await showModalBottomSheet<List<StockOpnameItemChoice>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SkuPickerSheet(group: group, items: items),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    if (_itemGroup != group) {
      setState(
        () => _error = 'Item Group sudah berubah. Silakan pilih SKU kembali.',
      );
      return;
    }
    final existing = {for (final line in _lines) line.itemCode};
    final fresh = [
      for (final item in selected)
        if (!existing.contains(item.code)) item,
    ];
    if (fresh.isEmpty) {
      setState(() => _error = 'Semua SKU yang dipilih sudah ada di tabel.');
      return;
    }
    setState(() {
      _busy = true;
      _busyText = 'Menambahkan SKU dan mengambil Stock Awal...';
      _error = null;
    });
    try {
      for (final item in fresh) {
        final awal = await _api.stockAwal(
          company: _company!,
          warehouse: _warehouse!,
          postingDate: _dateFormat.format(_postingDate),
          postingTime: _timeText(_postingTime),
          itemCode: item.code,
        );
        if (!mounted) return;
        _lines.add(_OpnameLine.fromChoice(item, awal));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  Future<void> _refreshStock() async {
    if ((_warehouse ?? '').trim().isEmpty || (_company ?? '').trim().isEmpty) {
      setState(
        () => _error = 'Isi Tanggal, Jam, dan Warehouse terlebih dahulu.',
      );
      return;
    }
    final filled = _lines.where((line) => line.itemCode.isNotEmpty).toList();
    if (filled.isEmpty) {
      setState(() => _error = 'Belum ada SKU yang dipilih.');
      return;
    }
    setState(() {
      _busy = true;
      _busyText = 'Memperbarui Stock Awal...';
      _error = null;
    });
    try {
      for (final line in filled) {
        final awal = await _api.stockAwal(
          company: _company!,
          warehouse: _warehouse!,
          postingDate: _dateFormat.format(_postingDate),
          postingTime: _timeText(_postingTime),
          itemCode: line.itemCode,
        );
        if (!mounted) return;
        line.stockAwal = awal;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final header = _headerError();
    if (header != null) {
      setState(() => _error = header);
      return;
    }
    final filled = _lines.where((line) => line.itemCode.isNotEmpty).toList();
    if (filled.isEmpty) {
      setState(() => _error = 'Pilih minimal satu SKU untuk Stock Opname.');
      return;
    }
    final seen = <String>{};
    for (final line in filled) {
      if (!seen.add(line.itemCode)) {
        setState(() => _error = 'SKU ${line.itemCode} tercatat lebih dari sekali.');
        return;
      }
      line.stockFisik = _parseQty(line.fisikCtrl.text);
      line.keterangan = line.noteCtrl.text.trim();
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = StockOpnameDraft(
        namingSeries: _series,
        company: _company!.trim(),
        postingDate: _postingDate,
        postingTime: _timeText(_postingTime),
        warehouse: _warehouse!.trim(),
        itemGroup: _itemGroup!.trim(),
        lines: [
          for (final line in filled)
            StockOpnameLine(
              itemCode: line.itemCode,
              itemName: line.itemName,
              itemGroup: line.itemGroup,
              stockAwal: line.stockAwal,
              stockFisik: line.stockFisik,
              uom: line.uom,
              sudahDicek: line.sudahDicek,
              keterangan: line.keterangan,
            ),
        ],
      );
      final existing = widget.existingName?.trim() ?? '';
      if (existing.isEmpty) {
        await _api.create(draft);
      } else {
        await _api.update(existing, draft);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context
        .watch<WarehouseStockState>()
        .stockCompanies
        .map((entry) => ErpItemOption(id: entry.key, label: entry.value))
        .toList();
    final warehouses = [
      for (final row in _companyWarehouses)
        ErpItemOption(
          id: row.name,
          label: row.displayName.isEmpty ? row.name : row.displayName,
        ),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          (widget.existingName ?? '').trim().isEmpty
              ? 'Buat Stock Opname'
              : 'Edit Stock Opname',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  if (_seriesOptions.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _seriesOptions.contains(_series)
                          ? _series
                          : _seriesOptions.first,
                      decoration: const InputDecoration(labelText: 'Series'),
                      items: [
                        for (final series in _seriesOptions)
                          DropdownMenuItem(value: series, child: Text(series)),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _series = value),
                    ),
                  if (_seriesOptions.length > 1) const SizedBox(height: 10),
                  ErpItemAutocompleteField(
                    label: 'Company',
                    selectedId: _company,
                    options: companies,
                    decoration: const InputDecoration(
                      labelText: 'Company',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                    onSelected: _saving ? (_) {} : (value) => _onCompany(value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _pickerTile(
                          icon: Icons.event_rounded,
                          label: 'Tanggal Opname',
                          value: _dateFormat.format(_postingDate),
                          onTap: _saving ? null : _pickDate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _pickerTile(
                          icon: Icons.schedule_rounded,
                          label: 'Jam Opname',
                          value: _timeText(_postingTime),
                          onTap: _saving ? null : _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ErpItemAutocompleteField(
                    label: 'Warehouse',
                    selectedId: _warehouse,
                    options: warehouses,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                    onSelected: _saving
                        ? (_) {}
                        : (value) => _onWarehouse(value),
                  ),
                  const SizedBox(height: 10),
                  ErpItemAutocompleteField(
                    label: 'Item Group',
                    selectedId: _itemGroup,
                    options: _groupOptions,
                    decoration: const InputDecoration(
                      labelText: 'Item Group',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    onSearch: (query) async {
                      final names = await _api.searchItemGroups(query);
                      return [
                        for (final name in names)
                          ErpItemOption(id: name, label: name),
                      ];
                    },
                    onSelected: _saving
                        ? (_) {}
                        : (value) => _onItemGroup(value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving || _busy ? null : _pickSkus,
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: const Text('Pilih SKU'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving || _busy ? null : _refreshStock,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Stock Awal'),
                        ),
                      ),
                    ],
                  ),
                  if (_busy && _busyText != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_busyText!)),
                      ],
                    ),
                  ],
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
                  for (var i = 0; i < _lines.length; i++) _lineCard(i),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving || _busy ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      (widget.existingName ?? '').trim().isEmpty
                          ? 'Simpan'
                          : 'Update',
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    final title = line.itemName.isEmpty ? line.itemCode : line.itemName;
    return Container(
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
          Row(
            children: [
              Expanded(
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
                  ],
                ),
              ),
              IconButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _lines.removeAt(index).dispose();
                      }),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StockAwalHighlight(qty: line.stockAwal, uom: line.uom),
          const SizedBox(height: 10),
          TextField(
            controller: line.fisikCtrl,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Stock Fisik (${line.uom})',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: line.noteCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Keterangan'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: line.sudahDicek,
            onChanged: _saving
                ? null
                : (value) => setState(() => line.sudahDicek = value ?? false),
            title: const Text('Sudah Dicek'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }
}

class _OpnameLine {
  final String itemCode;
  final String itemName;
  final String itemGroup;
  final String uom;
  double stockAwal;
  double stockFisik;
  bool sudahDicek;
  String keterangan;
  final fisikCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  _OpnameLine({
    required this.itemCode,
    required this.itemName,
    required this.itemGroup,
    required this.uom,
    required this.stockAwal,
    this.stockFisik = 0,
    this.sudahDicek = false,
    this.keterangan = '',
  }) {
    fisikCtrl.text = stockFisik == 0 ? '' : _qty(stockFisik);
    noteCtrl.text = keterangan;
  }

  factory _OpnameLine.fromChoice(StockOpnameItemChoice item, double awal) {
    return _OpnameLine(
      itemCode: item.code,
      itemName: item.name,
      itemGroup: item.itemGroup,
      uom: item.uom,
      stockAwal: awal,
    );
  }

  factory _OpnameLine.fromLine(StockOpnameLine line) {
    return _OpnameLine(
      itemCode: line.itemCode,
      itemName: line.itemName,
      itemGroup: line.itemGroup,
      uom: line.uom,
      stockAwal: line.stockAwal,
      stockFisik: line.stockFisik,
      sudahDicek: line.sudahDicek,
      keterangan: line.keterangan,
    );
  }

  void dispose() {
    fisikCtrl.dispose();
    noteCtrl.dispose();
  }
}

class _SkuPickerSheet extends StatefulWidget {
  final String group;
  final List<StockOpnameItemChoice> items;

  const _SkuPickerSheet({required this.group, required this.items});

  @override
  State<_SkuPickerSheet> createState() => _SkuPickerSheetState();
}

class _SkuPickerSheetState extends State<_SkuPickerSheet> {
  final _search = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _search.text.trim().toLowerCase();
    final filtered = widget.items.where((item) {
      if (keyword.isEmpty) return true;
      return item.name.toLowerCase().contains(keyword) ||
          item.code.toLowerCase().contains(keyword);
    }).toList();
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Text(
            'Pilih SKU - ${widget.group}',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cari Nama Barang',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_selected.length} SKU dipilih',
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('Item tidak ditemukan'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final checked = _selected.contains(item.code);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(item.code);
                            } else {
                              _selected.remove(item.code);
                            }
                          });
                        },
                        title: Text(item.name),
                        subtitle: Text(item.code),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (_selected.isEmpty) return;
              final chosen = [
                for (final item in widget.items)
                  if (_selected.contains(item.code)) item,
              ];
              Navigator.pop(context, chosen);
            },
            child: const Text('Tambahkan SKU'),
          ),
        ],
      ),
    );
  }
}

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.replaceFirst(RegExp(r'\.$'), '');
}

double _parseQty(String raw) {
  return double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
}

String _timeText(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute:00';
}

TimeOfDay _parseTime(String raw) {
  final parts = raw.split(':');
  final hour = parts.isEmpty ? 0 : int.tryParse(parts[0]) ?? 0;
  final minute = parts.length < 2 ? 0 : int.tryParse(parts[1]) ?? 0;
  return TimeOfDay(
    hour: hour.clamp(0, 23),
    minute: minute.clamp(0, 59),
  );
}
