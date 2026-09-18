import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/pos_ui.dart';

class CreatePosOpeningEntryScreen extends StatefulWidget {
  final String? editName;

  const CreatePosOpeningEntryScreen({super.key, this.editName});

  @override
  State<CreatePosOpeningEntryScreen> createState() =>
      _CreatePosOpeningEntryScreenState();
}

class _BalanceRow {
  String? modeOfPayment;
  final TextEditingController amountCtrl;

  _BalanceRow({this.modeOfPayment, String amount = '0'})
    : amountCtrl = TextEditingController(text: amount);

  void dispose() => amountCtrl.dispose();
}

class _CreatePosOpeningEntryScreenState
    extends State<CreatePosOpeningEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  List<String> _profiles = const [];
  List<String> _companies = const [];
  List<String> _modes = const [];
  List<String> _cashiers = const [];
  List<_BalanceRow> _balanceRows = [];

  String? _posProfile;
  String? _company;
  String? _cashier;
  bool _canSelectCashier = false;
  DateTime _periodStart = DateTime.now();
  DateTime _postingDate = DateTime.now();
  bool _setPostingDate = false;
  bool _loading = true;
  bool _saving = false;
  bool _loadingProfile = false;
  String? _error;

  bool get _isEditing => widget.editName?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final row in _balanceRows) {
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
      final state = context.read<PosState>();
      final profiles = await state.fetchSelectableProfileNames();
      final companies = await state.fetchNames('Company');
      final modes = await state.fetchNames(
        'Mode of Payment',
        filters: const [
          ['enabled', '=', 1],
        ],
      );
      if (!mounted) return;

      final cashier = state.currentUser?.trim() ?? '';
      final initialProfile = profiles.isNotEmpty ? profiles.first : null;

      setState(() {
        _profiles = profiles;
        _companies = companies;
        _modes = modes;
        _posProfile = initialProfile;
        _company = companies.isNotEmpty ? companies.first : null;
        _cashier = cashier.isEmpty ? null : cashier;
        _balanceRows = [
          _BalanceRow(modeOfPayment: modes.isNotEmpty ? modes.first : null),
        ];
      });

      if (initialProfile != null) {
        await _applyPosProfile(initialProfile);
      }
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
    final doc = await state.loadOpeningDocument(name);
    if (!mounted) return;

    final profile = doc['pos_profile']?.toString().trim() ?? '';
    final company = doc['company']?.toString().trim() ?? '';
    final cashier = doc['user']?.toString().trim() ?? '';
    final periodRaw = doc['period_start_date']?.toString() ?? '';
    final postingRaw = doc['posting_date']?.toString() ?? '';
    final setPosting = doc['set_posting_date'] == 1 ||
        doc['set_posting_date'] == true ||
        doc['set_posting_date']?.toString() == '1';

    DateTime? periodStart;
    try {
      periodStart = DateTime.tryParse(periodRaw.replaceFirst(' ', 'T'));
    } catch (_) {}
    DateTime? postingDate;
    try {
      postingDate = DateTime.tryParse(postingRaw);
    } catch (_) {}

    final rawBalance = doc['balance_details'];
    final balanceRows = <_BalanceRow>[];
    if (rawBalance is List) {
      for (final row in rawBalance.whereType<Map>()) {
        balanceRows.add(
          _BalanceRow(
            modeOfPayment: row['mode_of_payment']?.toString(),
            amount: (row['opening_amount'] ?? 0).toString(),
          ),
        );
      }
    }

    for (final row in _balanceRows) {
      row.dispose();
    }

    setState(() {
      if (profile.isNotEmpty) {
        _posProfile = profile;
        if (!_profiles.contains(profile)) {
          _profiles = [profile, ..._profiles];
        }
      }
      if (company.isNotEmpty) {
        _company = company;
        if (!_companies.contains(company)) {
          _companies = [company, ..._companies];
        }
      }
      if (cashier.isNotEmpty) {
        _cashier = cashier;
        if (!_cashiers.contains(cashier)) {
          _cashiers = [cashier, ..._cashiers];
        }
      }
      if (periodStart != null) _periodStart = periodStart;
      if (postingDate != null) _postingDate = postingDate;
      _setPostingDate = setPosting;
      _balanceRows = balanceRows.isEmpty ? [_BalanceRow()] : balanceRows;
    });
  }

  Future<void> _applyPosProfile(String profileName) async {
    setState(() => _loadingProfile = true);
    try {
      final state = context.read<PosState>();
      final doc = await state.loadProfileDocument(profileName);
      if (!mounted) return;

      final company = doc['company']?.toString().trim() ?? '';
      final profileModes = state.paymentModesFromProfile(doc);
      final modes = profileModes.isNotEmpty ? profileModes : _modes;
      final assignedUsers = state.assignedUsersFromProfile(doc);
      final currentUser = state.currentUser?.trim() ?? '';
      final isAssigned = state.isCurrentUserAssignedToProfile(doc);
      final canSelectCashier = !isAssigned && assignedUsers.isNotEmpty;
      final cashierOptions = canSelectCashier
          ? assignedUsers
          : <String>[
              if (currentUser.isNotEmpty) currentUser,
              ...assignedUsers,
            ];

      for (final row in _balanceRows) {
        row.dispose();
      }

      setState(() {
        if (company.isNotEmpty) _company = company;
        if (profileModes.isNotEmpty) {
          _modes = {...profileModes, ..._modes}.toList();
        }
        _cashiers = cashierOptions.toSet().toList();
        _canSelectCashier = canSelectCashier;
        if (!canSelectCashier) {
          _cashier = currentUser.isNotEmpty
              ? currentUser
              : (_cashiers.isNotEmpty ? _cashiers.first : null);
        } else if (_cashier == null || !_cashiers.contains(_cashier)) {
          _cashier = _cashiers.isNotEmpty ? _cashiers.first : null;
        }
        _balanceRows = modes.isEmpty
            ? [_BalanceRow()]
            : [for (final mode in modes) _BalanceRow(modeOfPayment: mode)];
      });
    } catch (_) {
      // Keep existing rows if profile detail cannot be loaded.
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _pickPeriodStart() async {
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
      if (!_setPostingDate) {
        _postingDate = DateTime(date.year, date.month, date.day);
      }
    });
  }

  Future<void> _pickPostingDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _postingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _postingDate = DateTime(date.year, date.month, date.day);
      _setPostingDate = true;
    });
  }

  void _addBalanceRow() {
    setState(() {
      final unused = _modes
          .where(
            (mode) => !_balanceRows.any((row) => row.modeOfPayment == mode),
          )
          .toList();
      _balanceRows.add(
        _BalanceRow(modeOfPayment: unused.isNotEmpty ? unused.first : null),
      );
    });
  }

  void _removeBalanceRow(int index) {
    if (_balanceRows.length <= 1) return;
    setState(() {
      _balanceRows[index].dispose();
      _balanceRows.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_posProfile == null || _company == null) {
      setState(() => _error = 'Lengkapi POS Profile dan Company.');
      return;
    }
    if (_cashier == null || _cashier!.trim().isEmpty) {
      setState(() => _error = 'Cashier wajib diisi.');
      return;
    }

    final balanceDetails = <Map<String, dynamic>>[];
    for (final row in _balanceRows) {
      final mode = row.modeOfPayment?.trim() ?? '';
      if (mode.isEmpty) {
        setState(() => _error = 'Setiap baris wajib punya Mode of Payment.');
        return;
      }
      final amount = double.tryParse(row.amountCtrl.text.trim());
      if (amount == null) {
        setState(() => _error = 'Opening Amount tidak valid.');
        return;
      }
      balanceDetails.add({
        'mode_of_payment': mode,
        'opening_amount': amount,
      });
    }
    if (balanceDetails.isEmpty) {
      setState(() => _error = 'Minimal satu Opening Balance Details.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final periodStart = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(_periodStart);
      final postingDate = DateFormat('yyyy-MM-dd').format(
        _setPostingDate ? _postingDate : _periodStart,
      );
      final payload = {
        'pos_profile': _posProfile,
        'company': _company,
        'user': _cashier,
        'period_start_date': periodStart,
        'posting_date': postingDate,
        'set_posting_date': _setPostingDate ? 1 : 0,
        'balance_details': balanceDetails,
      };
      if (_isEditing) {
        await state.updateOpeningEntry(widget.editName!.trim(), payload);
      } else {
        await state.createOpeningEntry(payload);
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
        title: Text(_isEditing ? 'Edit POS Opening Entry' : 'Buat POS Opening Entry'),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  PosSectionCard(
                    title: 'Detail Opening',
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('profile-${_posProfile ?? 'none'}'),
                        initialValue: _profiles.contains(_posProfile)
                            ? _posProfile
                            : null,
                        isExpanded: true,
                        decoration: posFieldDecoration('POS Profile *'),
                        items: [
                          for (final profile in _profiles)
                            DropdownMenuItem(
                              value: profile,
                              child: Text(
                                profile,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _loadingProfile
                            ? null
                            : (value) async {
                                setState(() => _posProfile = value);
                                if (value != null) {
                                  await _applyPosProfile(value);
                                }
                              },
                        validator: (value) =>
                            value == null ? 'POS Profile wajib' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('company-${_company ?? 'none'}'),
                        initialValue: _companies.contains(_company)
                            ? _company
                            : null,
                        isExpanded: true,
                        decoration: posFieldDecoration('Company *'),
                        items: [
                          for (final company in _companies)
                            DropdownMenuItem(
                              value: company,
                              child: Text(
                                company,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _company = value),
                        validator: (value) =>
                            value == null ? 'Company wajib' : null,
                      ),
                      const SizedBox(height: 12),
                      _DateFieldTile(
                        label: 'Period Start Date *',
                        value: DateFormat(
                          'dd-MM-yyyy HH:mm',
                        ).format(_periodStart),
                        hint: 'Asia/Jakarta',
                        icon: Icons.event_rounded,
                        onTap: _pickPeriodStart,
                      ),
                      const SizedBox(height: 12),
                      _DateFieldTile(
                        label: 'Posting Date *',
                        value: DateFormat('dd-MM-yyyy').format(_postingDate),
                        icon: Icons.calendar_today_rounded,
                        onTap: _pickPostingDate,
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _setPostingDate,
                        activeColor: AppColors.primary,
                        title: const Text(
                          'Set Posting Date',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _setPostingDate = value ?? false;
                            if (!_setPostingDate) {
                              _postingDate = DateTime(
                                _periodStart.year,
                                _periodStart.month,
                                _periodStart.day,
                              );
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      if (_canSelectCashier)
                        DropdownButtonFormField<String>(
                          key: ValueKey('cashier-${_cashier ?? 'none'}'),
                          initialValue: _cashiers.contains(_cashier)
                              ? _cashier
                              : null,
                          isExpanded: true,
                          decoration: posFieldDecoration('Cashier *'),
                          items: [
                            for (final cashier in _cashiers)
                              DropdownMenuItem(
                                value: cashier,
                                child: Text(
                                  cashier,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _cashier = value),
                          validator: (value) =>
                              value == null ? 'Cashier wajib' : null,
                        )
                      else
                        InputDecorator(
                          decoration: posFieldDecoration('Cashier *'),
                          child: Text(
                            _cashier?.isNotEmpty == true
                                ? _cashier!
                                : 'User login tidak tersedia',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      if (_loadingProfile) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(
                          color: AppColors.primary,
                          minHeight: 2,
                        ),
                      ],
                    ],
                  ),
                  PosSectionCard(
                    title: 'Opening Balance Details',
                    children: [
                      for (var i = 0; i < _balanceRows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _BalanceRowCard(
                          index: i,
                          row: _balanceRows[i],
                          modes: _modes,
                          canRemove: _balanceRows.length > 1,
                          onRemove: () => _removeBalanceRow(i),
                          onModeChanged: (value) {
                            setState(() {
                              _balanceRows[i].modeOfPayment = value;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addBalanceRow,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Add Row',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _saving
                          ? 'Menyimpan...'
                          : (_isEditing ? 'Update Opening' : 'Simpan Opening'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateFieldTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final VoidCallback onTap;

  const _DateFieldTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: posFieldDecoration(label).copyWith(
          suffixIcon: Icon(icon, color: AppColors.slate),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(
                hint!,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceRowCard extends StatelessWidget {
  final int index;
  final _BalanceRow row;
  final List<String> modes;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String?> onModeChanged;

  const _BalanceRowCard({
    required this.index,
    required this.row,
    required this.modes,
    required this.canRemove,
    required this.onRemove,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = modes.contains(row.modeOfPayment)
        ? row.modeOfPayment
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No. ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Hapus baris',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('mode-$index-${selected ?? 'none'}'),
            initialValue: selected,
            isExpanded: true,
            decoration: posFieldDecoration('Mode of Payment *'),
            items: [
              for (final mode in modes)
                DropdownMenuItem(
                  value: mode,
                  child: Text(mode, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onModeChanged,
            validator: (value) =>
                value == null ? 'Mode of Payment wajib' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: posFieldDecoration('Opening Amount *'),
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
        ],
      ),
    );
  }
}
