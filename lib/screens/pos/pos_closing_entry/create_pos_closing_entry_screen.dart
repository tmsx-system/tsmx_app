import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/pos_opening_entry.dart';
import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/pos_ui.dart';

class CreatePosClosingEntryScreen extends StatefulWidget {
  final String? editName;

  const CreatePosClosingEntryScreen({super.key, this.editName});

  @override
  State<CreatePosClosingEntryScreen> createState() =>
      _CreatePosClosingEntryScreenState();
}

class _CreatePosClosingEntryScreenState
    extends State<CreatePosClosingEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _closingAmountCtrl = TextEditingController(text: '0');

  List<PosOpeningEntry> _openOpenings = const [];
  List<String> _modes = const [];
  String? _openingId;
  String? _modeOfPayment;
  DateTime _periodEnd = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _editingDoc;

  bool get _isEditing => widget.editName?.trim().isNotEmpty == true;

  PosOpeningEntry? get _selectedOpening {
    if (_openingId == null) return null;
    final matches = _openOpenings.where((row) => row.id == _openingId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _closingAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      await state.refreshOpenings();
      final openings = state.openings
          .where((row) => row.docStatus == 1)
          .toList();
      final modes = await state.fetchNames(
        'Mode of Payment',
        filters: const [
          ['enabled', '=', 1],
        ],
      );
      if (!mounted) return;
      setState(() {
        _openOpenings = openings;
        _modes = modes;
        _openingId ??= openings.isNotEmpty ? openings.first.id : null;
        _modeOfPayment ??= modes.isNotEmpty ? modes.first : null;
        final opening = _selectedOpening;
        if (opening != null && opening.balanceDetails.isNotEmpty) {
          _modeOfPayment = opening.balanceDetails.first.modeOfPayment;
          _closingAmountCtrl.text =
              opening.balanceDetails.first.openingAmount.toStringAsFixed(2);
        }
      });
      if (_isEditing) {
        await _loadExisting(widget.editName!.trim());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExisting(String name) async {
    final state = context.read<PosState>();
    final doc = await state.loadClosingDocument(name);
    if (!mounted) return;

    final openingId = doc['pos_opening_entry']?.toString().trim() ?? '';
    final periodEndRaw = doc['period_end_date']?.toString() ?? '';
    final periodEnd = DateTime.tryParse(periodEndRaw.replaceFirst(' ', 'T'));
    final rows = doc['payment_reconciliation'];
    String? mode;
    String amount = '0';
    if (rows is List && rows.isNotEmpty && rows.first is Map) {
      final row = Map<String, dynamic>.from(rows.first as Map);
      mode = row['mode_of_payment']?.toString();
      amount = (row['closing_amount'] ?? 0).toString();
    }

    setState(() {
      _editingDoc = doc;
      if (openingId.isNotEmpty) _openingId = openingId;
      if (periodEnd != null) _periodEnd = periodEnd;
      if (mode != null && mode.isNotEmpty) {
        _modeOfPayment = mode;
        if (!_modes.contains(mode)) _modes = [mode, ..._modes];
      }
      _closingAmountCtrl.text = amount;
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _periodEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_periodEnd),
    );
    if (time == null || !mounted) return;
    setState(() {
      _periodEnd = DateTime(
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
    final opening = _selectedOpening;
    if (!_isEditing && (opening == null || _modeOfPayment == null)) {
      setState(() => _error = 'Pilih Opening Entry dan Mode of Payment.');
      return;
    }
    if (_modeOfPayment == null) {
      setState(() => _error = 'Pilih Mode of Payment.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final closingAmount = double.parse(_closingAmountCtrl.text.trim());
      final periodEnd = DateFormat('yyyy-MM-dd HH:mm:ss').format(_periodEnd);
      final postingDate = DateFormat('yyyy-MM-dd').format(_periodEnd);

      if (_isEditing) {
        final source = _editingDoc ?? await state.loadClosingDocument(
          widget.editName!.trim(),
        );
        final openingAmount = double.tryParse(
              (source['payment_reconciliation'] is List &&
                      (source['payment_reconciliation'] as List).isNotEmpty)
                  ? (((source['payment_reconciliation'] as List).first
                                as Map)['opening_amount'] ??
                            0)
                        .toString()
                  : '0',
            ) ??
            0;
        await state.updateClosingEntry(widget.editName!.trim(), {
          'period_end_date': periodEnd,
          'posting_date': postingDate,
          'payment_reconciliation': [
            {
              'mode_of_payment': _modeOfPayment,
              'opening_amount': openingAmount,
              'expected_amount': openingAmount,
              'closing_amount': closingAmount,
            },
          ],
        });
      } else {
        final openingAmount = opening!.balanceDetails
            .where((row) => row.modeOfPayment == _modeOfPayment)
            .fold<double>(0, (sum, row) => sum + row.openingAmount);

        await state.createClosingEntry({
          'pos_opening_entry': opening.id,
          'pos_profile': opening.posProfile,
          'company': opening.company,
          'user': state.currentUser ?? opening.user,
          'period_start_date': opening.periodStartDate,
          'period_end_date': periodEnd,
          'posting_date': postingDate,
          'payment_reconciliation': [
            {
              'mode_of_payment': _modeOfPayment,
              'opening_amount': openingAmount,
              'expected_amount': openingAmount,
              'closing_amount': closingAmount,
            },
          ],
        });
      }
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
        title: Text(_isEditing ? 'Edit POS Closing Entry' : 'Buat POS Closing Entry'),
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
                  if (!_isEditing && _openOpenings.isEmpty)
                    const Text(
                      'Tidak ada POS Opening Entry submitted. Buka sesi dulu.',
                      style: TextStyle(color: AppColors.slate),
                    )
                  else ...[
                    if (_isEditing)
                      InputDecorator(
                        decoration: posFieldDecoration('POS Opening Entry'),
                        child: Text(
                          _openingId ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey('opening-${_openingId ?? 'none'}'),
                        initialValue: _openingId,
                        decoration: posFieldDecoration('POS Opening Entry'),
                        items: [
                          for (final opening in _openOpenings)
                            DropdownMenuItem(
                              value: opening.id,
                              child: Text(
                                '${opening.id} • ${opening.posProfile}',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _openingId = value;
                            final opening = _selectedOpening;
                            if (opening != null &&
                                opening.balanceDetails.isNotEmpty) {
                              _modeOfPayment =
                                  opening.balanceDetails.first.modeOfPayment;
                              _closingAmountCtrl.text = opening
                                  .balanceDetails.first.openingAmount
                                  .toStringAsFixed(2);
                            }
                          });
                        },
                        validator: (value) =>
                            value == null ? 'Opening Entry wajib' : null,
                      ),
                    const SizedBox(height: 12),
                    if (_selectedOpening != null)
                      Text(
                        'Profile: ${_selectedOpening!.posProfile} • Company: ${_selectedOpening!.company}',
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Period End'),
                      subtitle: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(_periodEnd),
                      ),
                      trailing: const Icon(Icons.event_rounded),
                      onTap: _pickDateTime,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('mode-${_modeOfPayment ?? 'none'}'),
                      initialValue: _modes.contains(_modeOfPayment)
                          ? _modeOfPayment
                          : null,
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
                      controller: _closingAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: posFieldDecoration('Closing Amount'),
                      validator: (value) {
                        if (double.tryParse(value?.trim() ?? '') == null) {
                          return 'Closing Amount tidak valid';
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
                      child: Text(
                        _saving
                            ? 'Menyimpan...'
                            : (_isEditing
                                  ? 'Update Closing'
                                  : 'Simpan Closing'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
