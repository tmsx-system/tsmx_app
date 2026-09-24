import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/pos_opening_entry.dart';
import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_error_dialog.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/pos_ui.dart';

class CreatePosClosingEntryScreen extends StatefulWidget {
  final String? editName;

  const CreatePosClosingEntryScreen({super.key, this.editName});

  @override
  State<CreatePosClosingEntryScreen> createState() =>
      _CreatePosClosingEntryScreenState();
}

class _PosTxnRow {
  final String posInvoice;
  final String postingDate;
  final double grandTotal;
  final String customer;

  const _PosTxnRow({
    required this.posInvoice,
    required this.postingDate,
    required this.grandTotal,
    this.customer = '',
  });
}

class _PaymentReconcileRow {
  final String modeOfPayment;
  final double openingAmount;
  double expectedAmount;
  final TextEditingController closingCtrl;

  _PaymentReconcileRow({
    required this.modeOfPayment,
    this.openingAmount = 0,
    this.expectedAmount = 0,
    String closingAmount = '0',
  }) : closingCtrl = TextEditingController(text: closingAmount);

  double get closingAmount {
    final value = double.tryParse(closingCtrl.text.trim()) ?? 0;
    return value;
  }

  double get difference => closingAmount - expectedAmount;

  void dispose() => closingCtrl.dispose();
}

class _CreatePosClosingEntryScreenState
    extends State<CreatePosClosingEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  List<PosOpeningEntry> _openOpenings = const [];
  List<_PosTxnRow> _transactions = const [];
  List<_PaymentReconcileRow> _paymentRows = [];

  String? _openingId;
  String _company = '';
  String _posProfile = '';
  String _cashier = '';
  DateTime? _periodStart;
  DateTime _periodEnd = DateTime.now();
  DateTime _postingDate = DateTime.now();
  TimeOfDay _postingTime = TimeOfDay.now();

  double _grandTotal = 0;
  double _netTotal = 0;
  double _totalQty = 0;

  bool _loading = true;
  bool _loadingSession = false;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.editName?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final row in _paymentRows) {
      row.dispose();
    }
    super.dispose();
  }

  String _fmtDate(DateTime value) => DateFormat('dd-MM-yyyy').format(value);

  String _fmtDateTime(DateTime value) =>
      DateFormat('dd-MM-yyyy HH:mm:ss').format(value);

  String _fmtTime(TimeOfDay value) {
    final now = DateTime.now();
    final dt = DateTime(
      now.year,
      now.month,
      now.day,
      value.hour,
      value.minute,
      0,
    );
    return DateFormat('HH:mm:ss').format(dt);
  }

  String _toErpDateTime(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value);

  String _toErpDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      await state.refreshOpenings();
      var openings = state.openings.where((row) => row.docStatus == 1).toList();
      final openOnly = openings
          .where((row) => row.statusText.toLowerCase() == 'open')
          .toList();
      if (openOnly.isNotEmpty) openings = openOnly;

      if (!mounted) return;
      setState(() {
        _openOpenings = openings;
        _openingId ??= openings.isNotEmpty ? openings.first.id : null;
      });

      if (_isEditing) {
        await _loadExisting(widget.editName!.trim());
      } else if (_openingId != null) {
        await _applyOpening(_openingId!);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExisting(String name) async {
    final state = context.read<PosState>();
    final doc = await state.loadClosingDocument(name);
    if (!mounted) return;

    final openingId = doc['pos_opening_entry']?.toString().trim() ?? '';
    final company = doc['company']?.toString().trim() ?? '';
    final profile = doc['pos_profile']?.toString().trim() ?? '';
    final cashier = doc['user']?.toString().trim() ?? '';
    final periodStartRaw = doc['period_start_date']?.toString() ?? '';
    final periodEndRaw = doc['period_end_date']?.toString() ?? '';
    final postingDateRaw = doc['posting_date']?.toString() ?? '';
    final postingTimeRaw = doc['posting_time']?.toString() ?? '';

    final periodStart = DateTime.tryParse(
      periodStartRaw.replaceFirst(' ', 'T'),
    );
    final periodEnd = DateTime.tryParse(periodEndRaw.replaceFirst(' ', 'T'));
    final postingDate = DateTime.tryParse(postingDateRaw);
    TimeOfDay? postingTime;
    final timeParts = postingTimeRaw.split(':');
    if (timeParts.length >= 2) {
      postingTime = TimeOfDay(
        hour: int.tryParse(timeParts[0]) ?? 0,
        minute: int.tryParse(timeParts[1]) ?? 0,
      );
    }

    final txnSource =
        doc['pos_transactions'] ?? doc['pos_invoices'] ?? const [];
    final transactions = <_PosTxnRow>[];
    if (txnSource is List) {
      for (final row in txnSource.whereType<Map>()) {
        final invoice =
            (row['pos_invoice'] ?? row['sales_invoice'] ?? '').toString();
        if (invoice.isEmpty) continue;
        transactions.add(
          _PosTxnRow(
            posInvoice: invoice,
            postingDate: row['posting_date']?.toString() ?? '',
            grandTotal:
                double.tryParse(row['grand_total']?.toString() ?? '') ?? 0,
            customer: row['customer']?.toString() ?? '',
          ),
        );
      }
    }

    for (final row in _paymentRows) {
      row.dispose();
    }
    final paymentRows = <_PaymentReconcileRow>[];
    final rawPayments = doc['payment_reconciliation'];
    if (rawPayments is List) {
      for (final row in rawPayments.whereType<Map>()) {
        final mode = row['mode_of_payment']?.toString() ?? '';
        if (mode.isEmpty) continue;
        paymentRows.add(
          _PaymentReconcileRow(
            modeOfPayment: mode,
            openingAmount:
                double.tryParse(row['opening_amount']?.toString() ?? '') ?? 0,
            expectedAmount:
                double.tryParse(row['expected_amount']?.toString() ?? '') ?? 0,
            closingAmount: (row['closing_amount'] ?? 0).toString(),
          ),
        );
      }
    }

    setState(() {
      if (openingId.isNotEmpty) {
        _openingId = openingId;
        if (!_openOpenings.any((row) => row.id == openingId)) {
          _openOpenings = [
            PosOpeningEntry(
              id: openingId,
              company: company,
              posProfile: profile,
              user: cashier,
              periodStartDate: periodStartRaw,
              docStatus: 1,
              statusText: 'Open',
            ),
            ..._openOpenings,
          ];
        }
      }
      _company = company;
      _posProfile = profile;
      _cashier = cashier;
      if (periodStart != null) _periodStart = periodStart;
      if (periodEnd != null) _periodEnd = periodEnd;
      if (postingDate != null) _postingDate = postingDate;
      if (postingTime != null) _postingTime = postingTime;
      _transactions = transactions;
      _paymentRows = paymentRows;
      _grandTotal =
          double.tryParse(doc['grand_total']?.toString() ?? '') ??
          transactions.fold<double>(0, (sum, row) => sum + row.grandTotal);
      _netTotal = double.tryParse(doc['net_total']?.toString() ?? '') ?? 0;
      _totalQty = double.tryParse(doc['total_quantity']?.toString() ?? '') ?? 0;
    });
  }

  Future<void> _applyOpening(String openingId) async {
    setState(() {
      _loadingSession = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final doc = await state.loadOpeningDocument(openingId);
      if (!mounted) return;

      final company = doc['company']?.toString().trim() ?? '';
      final profile = doc['pos_profile']?.toString().trim() ?? '';
      final cashier = doc['user']?.toString().trim() ?? '';
      final periodStartRaw = doc['period_start_date']?.toString() ?? '';
      final periodStart = DateTime.tryParse(
        periodStartRaw.replaceFirst(' ', 'T'),
      );

      for (final row in _paymentRows) {
        row.dispose();
      }
      final paymentRows = <_PaymentReconcileRow>[];
      final balance = doc['balance_details'];
      if (balance is List) {
        for (final row in balance.whereType<Map>()) {
          final mode = row['mode_of_payment']?.toString() ?? '';
          if (mode.isEmpty) continue;
          final openingAmount =
              double.tryParse(row['opening_amount']?.toString() ?? '') ?? 0;
          paymentRows.add(
            _PaymentReconcileRow(
              modeOfPayment: mode,
              openingAmount: openingAmount,
              expectedAmount: openingAmount,
              closingAmount: openingAmount.toStringAsFixed(2),
            ),
          );
        }
      }

      setState(() {
        _openingId = openingId;
        _company = company;
        _posProfile = profile;
        _cashier = cashier;
        _periodStart = periodStart;
        _paymentRows = paymentRows;
        _transactions = const [];
        _grandTotal = 0;
        _netTotal = 0;
        _totalQty = 0;
      });

      await _reloadInvoices();
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  Future<void> _reloadInvoices() async {
    if (_posProfile.isEmpty || _cashier.isEmpty || _periodStart == null) {
      return;
    }

    setState(() => _loadingSession = true);
    try {
      final state = context.read<PosState>();
      final invoices = await state.fetchPosInvoicesForClosing(
        start: _toErpDateTime(_periodStart!),
        end: _toErpDateTime(_periodEnd),
        posProfile: _posProfile,
        user: _cashier,
      );
      if (!mounted) return;

      final transactions = <_PosTxnRow>[];
      var grandTotal = 0.0;
      var netTotal = 0.0;
      var totalQty = 0.0;

      // Reset expected to opening amounts first.
      for (final row in _paymentRows) {
        row.expectedAmount = row.openingAmount;
      }

      for (final invoice in invoices) {
        final name = invoice['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final amount =
            double.tryParse(invoice['grand_total']?.toString() ?? '') ?? 0;
        final net =
            double.tryParse(invoice['net_total']?.toString() ?? '') ?? 0;
        final qty =
            double.tryParse(invoice['total_qty']?.toString() ?? '') ?? 0;

        transactions.add(
          _PosTxnRow(
            posInvoice: name,
            postingDate: invoice['posting_date']?.toString() ?? '',
            grandTotal: amount,
            customer: invoice['customer']?.toString() ?? '',
          ),
        );
        grandTotal += amount;
        netTotal += net;
        totalQty += qty;

        final payments = invoice['payments'];
        if (payments is List) {
          final changeAmount =
              double.tryParse(invoice['change_amount']?.toString() ?? '') ?? 0;
          final changeAccount =
              invoice['account_for_change_amount']?.toString() ?? '';
          for (final payment in payments.whereType<Map>()) {
            final mode = payment['mode_of_payment']?.toString() ?? '';
            if (mode.isEmpty) continue;
            var payAmount =
                double.tryParse(payment['amount']?.toString() ?? '') ?? 0;
            final account = payment['account']?.toString() ?? '';
            if (changeAccount.isNotEmpty &&
                account == changeAccount &&
                changeAmount > 0) {
              payAmount -= changeAmount;
            }
            final existing = _paymentRows.where(
              (row) => row.modeOfPayment == mode,
            );
            if (existing.isNotEmpty) {
              existing.first.expectedAmount += payAmount;
            } else {
              _paymentRows.add(
                _PaymentReconcileRow(
                  modeOfPayment: mode,
                  openingAmount: 0,
                  expectedAmount: payAmount,
                  closingAmount: '0',
                ),
              );
            }
          }
        }
      }

      // Default closing amount = expected when still zero / untouched create.
      for (final row in _paymentRows) {
        final current = double.tryParse(row.closingCtrl.text.trim());
        if (current == null || current == row.openingAmount || current == 0) {
          row.closingCtrl.text = row.expectedAmount.toStringAsFixed(2);
        }
      }

      setState(() {
        _transactions = transactions;
        _grandTotal = grandTotal;
        _netTotal = netTotal;
        _totalQty = totalQty;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  Future<void> _pickPeriodEnd() async {
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
    await _reloadInvoices();
  }

  Future<void> _pickPostingDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _postingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() => _postingDate = date);
  }

  Future<void> _pickPostingTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _postingTime,
    );
    if (time == null || !mounted) return;
    setState(() => _postingTime = time);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_openingId == null || _openingId!.isEmpty) {
      setState(() => _error = 'POS Opening Entry wajib dipilih.');
      return;
    }
    if (_company.isEmpty || _posProfile.isEmpty || _cashier.isEmpty) {
      setState(() => _error = 'Company, POS Profile, dan Cashier wajib.');
      return;
    }
    if (_paymentRows.isEmpty) {
      setState(() => _error = 'Payment Reconciliation masih kosong.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final periodStart = _periodStart ?? _periodEnd;
      final payload = {
        'pos_opening_entry': _openingId,
        'company': _company,
        'pos_profile': _posProfile,
        'user': _cashier,
        'period_start_date': _toErpDateTime(periodStart),
        'period_end_date': _toErpDateTime(_periodEnd),
        'posting_date': _toErpDate(_postingDate),
        'posting_time': _fmtTime(_postingTime),
        'grand_total': _grandTotal,
        'net_total': _netTotal,
        'total_quantity': _totalQty,
        'pos_transactions': [
          for (final row in _transactions)
            {
              'pos_invoice': row.posInvoice,
              'posting_date': row.postingDate,
              'grand_total': row.grandTotal,
              if (row.customer.isNotEmpty) 'customer': row.customer,
            },
        ],
        'payment_reconciliation': [
          for (final row in _paymentRows)
            {
              'mode_of_payment': row.modeOfPayment,
              'opening_amount': row.openingAmount,
              'expected_amount': row.expectedAmount,
              'closing_amount': row.closingAmount,
              'difference': row.difference,
            },
        ],
      };

      if (_isEditing) {
        await state.updateClosingEntry(widget.editName!.trim(), payload);
      } else {
        try {
          await state.createClosingEntry(payload);
        } catch (error) {
          // Newer ERPNext uses pos_invoices instead of pos_transactions.
          final message = error.toString().toLowerCase();
          if (message.contains('pos_transactions') ||
              message.contains('unknown field') ||
              message.contains('not permitted')) {
            final alt = Map<String, dynamic>.from(payload)
              ..remove('pos_transactions')
              ..['pos_invoices'] = [
                for (final row in _transactions)
                  {
                    'pos_invoice': row.posInvoice,
                    'posting_date': row.postingDate,
                    'grand_total': row.grandTotal,
                    if (row.customer.isNotEmpty) 'customer': row.customer,
                  },
              ];
            await state.createClosingEntry(alt);
          } else {
            rethrow;
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
    IconData icon = Icons.event_rounded,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: posFieldDecoration(
          label,
          suffixIcon: Icon(icon, color: AppColors.slate),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _readonlyField(String label, String value) {
    return InputDecorator(
      decoration: posFieldDecoration(label),
      child: Text(
        value.isEmpty ? '-' : value,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          _isEditing ? 'Edit POS Closing Entry' : 'Buat POS Closing Entry',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? '...' : 'Save',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: TmsxResponsive.pagePadding(
                  context,
                  top: 16,
                  bottom: 28,
                ),
                child: TmsxResponsiveBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFC2410C),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!_isEditing && _openOpenings.isEmpty)
                        PosSectionCard(
                          title: 'Informasi',
                          children: const [
                            Text(
                              'Tidak ada POS Opening Entry yang masih Open. Buka sesi dulu.',
                              style: TextStyle(
                                color: AppColors.slate,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        PosSectionCard(
                          title: 'Period Details',
                          children: [
                            _dateField(
                              label: 'Period End Date *',
                              value: _fmtDateTime(_periodEnd),
                              onTap: _pickPeriodEnd,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _dateField(
                                    label: 'Posting Date *',
                                    value: _fmtDate(_postingDate),
                                    onTap: _pickPostingDate,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _dateField(
                                    label: 'Posting Time *',
                                    value: _fmtTime(_postingTime),
                                    onTap: _pickPostingTime,
                                    icon: Icons.schedule_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_isEditing)
                              _readonlyField(
                                'POS Opening Entry',
                                _openingId ?? '-',
                              )
                            else
                              DropdownButtonFormField<String>(
                                key: ValueKey('opening-${_openingId ?? 'none'}'),
                                initialValue: _openOpenings.any(
                                  (row) => row.id == _openingId,
                                )
                                    ? _openingId
                                    : null,
                                isExpanded: true,
                                decoration: posFieldDecoration(
                                  'POS Opening Entry *',
                                ),
                                items: [
                                  for (final opening in _openOpenings)
                                    DropdownMenuItem(
                                      value: opening.id,
                                      child: Text(
                                        '${opening.id} • ${opening.posProfile}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _loadingSession
                                    ? null
                                    : (value) async {
                                        if (value == null) return;
                                        await _applyOpening(value);
                                      },
                                validator: (value) => value == null
                                    ? 'POS Opening Entry wajib'
                                    : null,
                              ),
                            if (_periodStart != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Period Start: ${_fmtDateTime(_periodStart!)}',
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        PosSectionCard(
                          title: 'User Details',
                          children: [
                            _readonlyField('Company', _company),
                            const SizedBox(height: 12),
                            _readonlyField('POS Profile', _posProfile),
                            const SizedBox(height: 12),
                            _readonlyField('Cashier', _cashier),
                          ],
                        ),
                        PosSectionCard(
                          title: 'POS Transactions',
                          children: [
                            if (_loadingSession)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            else if (_transactions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inbox_outlined,
                                      size: 36,
                                      color: AppColors.slate,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'No Data',
                                      style: TextStyle(
                                        color: AppColors.slate,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (var i = 0; i < _transactions.length; i++) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _TxnCard(index: i, row: _transactions[i]),
                              ],
                          ],
                        ),
                        PosSectionCard(
                          title: 'Payment Reconciliation',
                          children: [
                            if (_paymentRows.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.payments_outlined,
                                      size: 36,
                                      color: AppColors.slate,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'No Data',
                                      style: TextStyle(
                                        color: AppColors.slate,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (var i = 0; i < _paymentRows.length; i++) ...[
                                if (i > 0) const SizedBox(height: 12),
                                _PaymentCard(
                                  index: i,
                                  row: _paymentRows[i],
                                  onChanged: () => setState(() {}),
                                ),
                              ],
                          ],
                        ),
                        PosSectionCard(
                          title: 'Totals',
                          children: [
                            _TotalRow(
                              label: 'Grand Total',
                              value: 'Rp ${formatErpCurrency(_grandTotal)}',
                              emphasize: true,
                            ),
                            _TotalRow(
                              label: 'Net Total',
                              value: 'Rp ${formatErpCurrency(_netTotal)}',
                            ),
                            _TotalRow(
                              label: 'Total Qty',
                              value: _totalQty.toStringAsFixed(0),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _saving || _loadingSession ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _saving
                                ? 'Menyimpan...'
                                : (_isEditing
                                      ? 'Update Closing'
                                      : 'Simpan Closing'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TxnCard extends StatelessWidget {
  final int index;
  final _PosTxnRow row;

  const _TxnCard({required this.index, required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'No. ${index + 1}',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            row.posInvoice,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          if (row.customer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.customer,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  row.postingDate.isEmpty ? '-' : row.postingDate,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Rp ${formatErpCurrency(row.grandTotal)}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final int index;
  final _PaymentReconcileRow row;
  final VoidCallback onChanged;

  const _PaymentCard({
    required this.index,
    required this.row,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final differenceColor = row.difference == 0
        ? AppColors.navy
        : (row.difference < 0 ? AppColors.danger : AppColors.primary);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Pay ${index + 1} • ${row.modeOfPayment}',
              style: const TextStyle(
                color: Color(0xFFC2410C),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AmountBox(
                  label: 'Opening',
                  value: 'Rp ${formatErpCurrency(row.openingAmount)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AmountBox(
                  label: 'Expected',
                  value: 'Rp ${formatErpCurrency(row.expectedAmount)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.closingCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: posFieldDecoration(
              'Closing Amount *',
            ).copyWith(fillColor: AppColors.white),
            onChanged: (_) => onChanged(),
            validator: (value) {
              if (double.tryParse(value?.trim() ?? '') == null) {
                return 'Closing Amount tidak valid';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Text(
                  'Difference',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Rp ${formatErpCurrency(row.difference)}',
                  style: TextStyle(
                    color: differenceColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountBox extends StatelessWidget {
  final String label;
  final String value;

  const _AmountBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? AppColors.navy : AppColors.slate,
                fontSize: emphasize ? 14 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: emphasize ? 15 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
