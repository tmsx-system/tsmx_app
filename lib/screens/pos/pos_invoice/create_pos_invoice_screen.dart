import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/pos_ui.dart';

class CreatePosInvoiceScreen extends StatefulWidget {
  const CreatePosInvoiceScreen({super.key});

  @override
  State<CreatePosInvoiceScreen> createState() => _CreatePosInvoiceScreenState();
}

class _CreatePosInvoiceScreenState extends State<CreatePosInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rateCtrl = TextEditingController(text: '0');

  List<String> _profiles = const [];
  List<_LinkOption> _customers = const [];
  List<_LinkOption> _items = const [];
  List<String> _modes = const [];
  String? _posProfile;
  String? _customer;
  String? _itemCode;
  String? _modeOfPayment;
  DateTime _postingDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final profiles = await state.fetchNames(
        'POS Profile',
        filters: const [
          ['disabled', '=', 0],
        ],
      );
      final customerRows = await state.fetchLinkOptions(
        'Customer',
        fields: const ['name', 'customer_name'],
        filters: const [
          ['disabled', '=', 0],
        ],
        orderBy: 'customer_name asc',
      );
      final itemRows = await state.fetchLinkOptions(
        'Item',
        fields: const ['name', 'item_name', 'standard_rate'],
        filters: const [
          ['disabled', '=', 0],
          ['is_sales_item', '=', 1],
        ],
        orderBy: 'item_name asc',
      );
      final modes = await state.fetchNames(
        'Mode of Payment',
        filters: const [
          ['enabled', '=', 1],
        ],
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _customers = customerRows
            .map(
              (row) => _LinkOption(
                id: row['name']?.toString() ?? '',
                label:
                    row['customer_name']?.toString() ??
                    row['name']?.toString() ??
                    '',
              ),
            )
            .where((row) => row.id.isNotEmpty)
            .toList();
        _items = itemRows
            .map(
              (row) => _LinkOption(
                id: row['name']?.toString() ?? '',
                label:
                    row['item_name']?.toString() ??
                    row['name']?.toString() ??
                    '',
                rate: double.tryParse(row['standard_rate']?.toString() ?? '') ??
                    0,
              ),
            )
            .where((row) => row.id.isNotEmpty)
            .toList();
        _modes = modes;
        _posProfile ??= profiles.isNotEmpty ? profiles.first : null;
        _customer ??= _customers.isNotEmpty ? _customers.first.id : null;
        _itemCode ??= _items.isNotEmpty ? _items.first.id : null;
        _modeOfPayment ??= modes.isNotEmpty ? modes.first : null;
        if (_itemCode != null) {
          final selected = _items.where((item) => item.id == _itemCode);
          if (selected.isNotEmpty) {
            _rateCtrl.text = selected.first.rate.toStringAsFixed(2);
          }
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _postingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() => _postingDate = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_posProfile == null ||
        _customer == null ||
        _itemCode == null ||
        _modeOfPayment == null) {
      setState(() => _error = 'Lengkapi semua field wajib.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final qty = double.parse(_qtyCtrl.text.trim());
      final rate = double.parse(_rateCtrl.text.trim());
      final amount = qty * rate;
      final postingDate = DateFormat('yyyy-MM-dd').format(_postingDate);

      String company = '';
      try {
        final profile = await state.loadProfileDetail(_posProfile!);
        company = profile.company;
      } catch (_) {}

      await state.createInvoice({
        'is_pos': 1,
        'pos_profile': _posProfile,
        'customer': _customer,
        if (company.isNotEmpty) 'company': company,
        'posting_date': postingDate,
        'items': [
          {
            'item_code': _itemCode,
            'qty': qty,
            'rate': rate,
            'amount': amount,
          },
        ],
        'payments': [
          {
            'mode_of_payment': _modeOfPayment,
            'amount': amount,
          },
        ],
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Buat POS Invoice'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _posProfile,
                    decoration: posFieldDecoration('POS Profile'),
                    items: [
                      for (final profile in _profiles)
                        DropdownMenuItem(value: profile, child: Text(profile)),
                    ],
                    onChanged: (value) => setState(() => _posProfile = value),
                    validator: (value) =>
                        value == null ? 'POS Profile wajib' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _customer,
                    decoration: posFieldDecoration('Customer'),
                    items: [
                      for (final customer in _customers)
                        DropdownMenuItem(
                          value: customer.id,
                          child: Text(customer.label),
                        ),
                    ],
                    onChanged: (value) => setState(() => _customer = value),
                    validator: (value) =>
                        value == null ? 'Customer wajib' : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Posting Date'),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(_postingDate)),
                    trailing: const Icon(Icons.event_rounded),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _itemCode,
                    decoration: posFieldDecoration('Item'),
                    items: [
                      for (final item in _items)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text('${item.id} - ${item.label}'),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _itemCode = value;
                        final selected = _items.where((item) => item.id == value);
                        if (selected.isNotEmpty) {
                          _rateCtrl.text =
                              selected.first.rate.toStringAsFixed(2);
                        }
                      });
                    },
                    validator: (value) => value == null ? 'Item wajib' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: posFieldDecoration('Qty'),
                    validator: (value) {
                      final qty = double.tryParse(value?.trim() ?? '');
                      if (qty == null || qty <= 0) return 'Qty tidak valid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: posFieldDecoration('Rate'),
                    validator: (value) {
                      final rate = double.tryParse(value?.trim() ?? '');
                      if (rate == null || rate < 0) return 'Rate tidak valid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _modeOfPayment,
                    decoration: posFieldDecoration('Mode of Payment'),
                    items: [
                      for (final mode in _modes)
                        DropdownMenuItem(value: mode, child: Text(mode)),
                    ],
                    onChanged: (value) =>
                        setState(() => _modeOfPayment = value),
                    validator: (value) =>
                        value == null ? 'Mode of Payment wajib' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_saving ? 'Menyimpan...' : 'Simpan Invoice'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _LinkOption {
  final String id;
  final String label;
  final double rate;

  const _LinkOption({required this.id, required this.label, this.rate = 0});
}
