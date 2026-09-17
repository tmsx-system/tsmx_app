import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/pos_ui.dart';

class CreatePosOpeningEntryScreen extends StatefulWidget {
  const CreatePosOpeningEntryScreen({super.key});

  @override
  State<CreatePosOpeningEntryScreen> createState() =>
      _CreatePosOpeningEntryScreenState();
}

class _CreatePosOpeningEntryScreenState
    extends State<CreatePosOpeningEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController(text: '0');

  List<String> _profiles = const [];
  List<String> _companies = const [];
  List<String> _modes = const [];
  String? _posProfile;
  String? _company;
  String? _modeOfPayment;
  DateTime _periodStart = DateTime.now();
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
    _amountCtrl.dispose();
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
      final companies = await state.fetchNames('Company');
      final modes = await state.fetchNames(
        'Mode of Payment',
        filters: const [
          ['enabled', '=', 1],
        ],
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _companies = companies;
        _modes = modes;
        _posProfile ??= profiles.isNotEmpty ? profiles.first : null;
        _company ??= companies.isNotEmpty ? companies.first : null;
        _modeOfPayment ??= modes.isNotEmpty ? modes.first : null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _periodStart,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_periodStart),
    );
    if (time == null || !mounted) return;
    setState(() {
      _periodStart = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_posProfile == null || _company == null || _modeOfPayment == null) {
      setState(() => _error = 'Lengkapi POS Profile, Company, dan Mode of Payment.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
      final periodStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(_periodStart);
      final postingDate = DateFormat('yyyy-MM-dd').format(_periodStart);
      await state.createOpeningEntry({
        'pos_profile': _posProfile,
        'company': _company,
        'user': state.currentUser,
        'period_start_date': periodStart,
        'posting_date': postingDate,
        'balance_details': [
          {
            'mode_of_payment': _modeOfPayment,
            'opening_amount': amount,
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
        title: const Text('Buat POS Opening Entry'),
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
                    initialValue: _company,
                    decoration: posFieldDecoration('Company'),
                    items: [
                      for (final company in _companies)
                        DropdownMenuItem(value: company, child: Text(company)),
                    ],
                    onChanged: (value) => setState(() => _company = value),
                    validator: (value) =>
                        value == null ? 'Company wajib' : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Period Start'),
                    subtitle: Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(_periodStart),
                    ),
                    trailing: const Icon(Icons.event_rounded),
                    onTap: _pickDateTime,
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: posFieldDecoration('Opening Amount'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Opening Amount wajib';
                      }
                      if (double.tryParse(value.trim()) == null) {
                        return 'Angka tidak valid';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_saving ? 'Menyimpan...' : 'Simpan Opening'),
                  ),
                ],
              ),
            ),
    );
  }
}
