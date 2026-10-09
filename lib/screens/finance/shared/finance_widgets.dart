part of '../finance_main_screen.dart';

class _FinancePeriodCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final int selectedYear;
  final int selectedMonth;
  final bool loading;
  final void Function(int year, int month) onChanged;
  final List<String> companyOptions;
  final String selectedCompany;
  final ValueChanged<String>? onCompanyChanged;

  const _FinancePeriodCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedYear,
    required this.selectedMonth,
    required this.loading,
    required this.onChanged,
    required this.companyOptions,
    required this.selectedCompany,
    required this.onCompanyChanged,
  });

  static const monthLabels = ErpPeriodFilterCard.monthLabels;

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = [
      for (var year = currentYear; year >= currentYear - 5; year--) year,
    ];
    final companies = [
      ...companyOptions,
      if (selectedCompany.isNotEmpty &&
          !companyOptions.contains(selectedCompany))
        selectedCompany,
    ]..sort();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _financeCardDecoration(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FinanceIconBox(icon: icon, color: _financeGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _financeGreen,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _FinanceDropdown<int>(
                  label: 'Bulan',
                  icon: Icons.calendar_today_rounded,
                  value: selectedMonth,
                  enabled: !loading,
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('Semua Bulan'),
                    ),
                    for (var i = 0; i < monthLabels.length; i++)
                      DropdownMenuItem(
                        value: i + 1,
                        child: Text(monthLabels[i]),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(selectedYear, value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _FinanceDropdown<int>(
                  label: 'Tahun',
                  icon: Icons.event_available_rounded,
                  value: selectedYear,
                  enabled: !loading,
                  items: [
                    for (final year in years)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(value, selectedMonth);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ErpSearchableFilterField(
            label: 'Perusahaan',
            selectedId: selectedCompany,
            decoration: const InputDecoration(
              labelText: 'Perusahaan',
              prefixIcon: Icon(Icons.business_rounded, size: 18),
            ),
            allLabel: 'Semua perusahaan',
            options: [
              for (final company in companies)
                ErpItemOption(id: company, label: company),
            ],
            onSelected: loading
                ? (_) {}
                : (value) => onCompanyChanged?.call(value ?? ''),
          ),
        ],
      ),
    );
  }
}

class _FinanceDropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final bool enabled;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FinanceDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
      ),
      items: items,
      onChanged: enabled ? onChanged : null,
    );
  }
}

void _showDocumentRows(
  BuildContext context, {
  required String title,
  required List<FinanceDocumentRow> rows,
  required String emptyTitle,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinanceListSheet(
      title: title,
      emptyTitle: emptyTitle,
      children: [
        for (final row in rows)
          _DocumentRow(
            row: row,
            doctype: row.status == 'Receive' || row.status == 'Pay'
                ? 'Payment Entry'
                : '',
          ),
      ],
    ),
  );
}

void _showTrendDetails(
  BuildContext context, {
  required String title,
  required List<DocumentTrendPoint> points,
  required List<FinanceReportMetric> reportRows,
}) {
  final summary = _TrendSummary.from(points);
  final rows = reportRows.isNotEmpty
      ? [
          for (final row in reportRows)
            _SimpleRow(
              title: row.label,
              subtitle: 'ERPNext Query Report',
              trailing: 'Amount',
              amount: row.value,
            ),
        ]
      : [
          _SimpleRow(
            title: 'Total',
            subtitle: 'Akumulasi dari bar chart aktif',
            trailing: 'Amount',
            amount: summary.total,
          ),
          _SimpleRow(
            title: 'Rata-rata',
            subtitle: '${points.length} periode',
            trailing: 'Average',
            amount: summary.average,
          ),
          _SimpleRow(
            title: 'Tertinggi',
            subtitle: summary.highestLabel,
            trailing: 'Peak',
            amount: summary.highest,
          ),
          _SimpleRow(
            title: 'Terendah',
            subtitle: summary.lowestLabel,
            trailing: 'Low',
            amount: summary.lowest,
          ),
          _SimpleRow(
            title: summary.directionTitle,
            subtitle: summary.directionSubtitle,
            trailing: 'Trend',
            amount: summary.delta,
          ),
        ];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinanceListSheet(
      title: title,
      emptyTitle: 'Belum ada data trend',
      children: rows,
    ),
  );
}

void _showBankBalances(BuildContext context, List<FinanceBankBalance> rows) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinanceListSheet(
      title: 'Bank Balance Monitoring',
      emptyTitle: 'Belum ada rekening bank',
      children: [for (final row in rows) _BankBalanceRow(row: row)],
    ),
  );
}

void _showBankBalance(BuildContext context, FinanceBankBalance row) {
  showErpDetailSheet(
    context: context,
    title: row.account,
    subtitle: 'Bank Account',
    statusText: 'Balance',
    rows: [
      ErpDetailRow(label: 'Account', value: row.account),
      ErpDetailRow(
        label: 'Balance',
        value: 'Rp ${formatErpCurrency(row.balance.abs())}',
      ),
    ],
  );
}

class _FinanceListSheet extends StatelessWidget {
  final String title;
  final String emptyTitle;
  final List<Widget> children;

  const _FinanceListSheet({
    required this.title,
    required this.emptyTitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return TmsxResponsiveBody(
          maxWidth: 680,
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: ListView(
              controller: controller,
              padding: TmsxResponsive.pagePadding(context, top: 10, bottom: 28),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (children.isEmpty)
                  ErpEmptyState(title: emptyTitle)
                else
                  ...children,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricData {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool currency;
  final VoidCallback? onTap;

  const _MetricData(
    this.label,
    this.value,
    this.icon, {
    this.color = _financeGreen,
    this.currency = true,
    this.onTap,
  });
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> metrics;

  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricData metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final value = metric.currency
        ? 'Rp ${formatErpCurrency(metric.value.abs())}'
        : metric.value.toInt().toString();
    return InkWell(
      onTap: metric.onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(16),
        decoration: _financeCardDecoration(radius: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FinanceIconBox(icon: metric.icon, color: metric.color),
            const SizedBox(height: 18),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final String title;
  final List<DocumentTrendPoint> points;
  final VoidCallback? onTap;

  const _TrendCard({required this.title, required this.points, this.onTap});

  @override
  Widget build(BuildContext context) {
    final summary = _TrendSummary.from(points);
    final maxValue = points.fold<double>(
      0,
      (max, point) => point.value.abs() > max ? point.value.abs() : max,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: _SectionCard(
        title: title,
        icon: Icons.show_chart_rounded,
        color: _financeCyan,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _TrendSummaryPill(
                    label: 'Total',
                    value: _compactMoney(summary.total),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TrendSummaryPill(
                    label: 'Rata-rata',
                    value: _compactMoney(summary.average),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TrendSummaryPill(
                    label: 'Trend',
                    value: summary.directionShort,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 164,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _compactMoney(point.value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxValue == 0
                                      ? 0.04
                                      : (point.value.abs() / maxValue).clamp(
                                          0.04,
                                          1,
                                        ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: point.value < 0
                                          ? _financeOrange
                                          : _financeCyan,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              point.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _TrendSummaryPill extends StatelessWidget {
  final String label;
  final String value;

  const _TrendSummaryPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        border: Border.all(color: _financeGreen.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _financeGreen,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendSummary {
  final double total;
  final double average;
  final double highest;
  final String highestLabel;
  final double lowest;
  final String lowestLabel;
  final double delta;

  const _TrendSummary({
    required this.total,
    required this.average,
    required this.highest,
    required this.highestLabel,
    required this.lowest,
    required this.lowestLabel,
    required this.delta,
  });

  factory _TrendSummary.from(List<DocumentTrendPoint> points) {
    if (points.isEmpty) {
      return const _TrendSummary(
        total: 0,
        average: 0,
        highest: 0,
        highestLabel: '-',
        lowest: 0,
        lowestLabel: '-',
        delta: 0,
      );
    }
    final total = points.fold<double>(0, (sum, point) => sum + point.value);
    var highest = points.first;
    var lowest = points.first;
    for (final point in points) {
      if (point.value > highest.value) highest = point;
      if (point.value < lowest.value) lowest = point;
    }
    final firstNonZero = points.cast<DocumentTrendPoint?>().firstWhere(
      (point) => point != null && point.value != 0,
      orElse: () => points.first,
    )!;
    final lastNonZero = points.reversed.cast<DocumentTrendPoint?>().firstWhere(
      (point) => point != null && point.value != 0,
      orElse: () => points.last,
    )!;
    return _TrendSummary(
      total: total,
      average: total / points.length,
      highest: highest.value,
      highestLabel: highest.label,
      lowest: lowest.value,
      lowestLabel: lowest.label,
      delta: lastNonZero.value - firstNonZero.value,
    );
  }

  String get directionShort {
    if (delta > 0) return 'Naik';
    if (delta < 0) return 'Turun';
    return 'Stabil';
  }

  String get directionTitle => 'Trend $directionShort';

  String get directionSubtitle {
    if (delta > 0) return 'Naik ${_compactMoney(delta)} dari periode awal';
    if (delta < 0) {
      return 'Turun ${_compactMoney(delta.abs())} dari periode awal';
    }
    return 'Tidak ada perubahan dari periode awal';
  }
}

String _compactMoney(double value) {
  final abs = value.abs();
  final prefix = value < 0 ? '-' : '';
  if (abs >= 1000000000) {
    return '${prefix}Rp ${(abs / 1000000000).toStringAsFixed(1)} M';
  }
  if (abs >= 1000000) {
    return '${prefix}Rp ${(abs / 1000000).toStringAsFixed(1)} jt';
  }
  if (abs >= 1000) {
    return '${prefix}Rp ${(abs / 1000).toStringAsFixed(0)} rb';
  }
  return '$prefix${formatErpCurrency(abs)}';
}

class _ReportSection extends StatelessWidget {
  final String title;
  final List<FinanceReportMetric> rows;

  const _ReportSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      icon: Icons.analytics_rounded,
      color: title.toLowerCase().contains('balance')
          ? _financePurple
          : _financeCyan,
      child: rows.isEmpty
          ? const ErpEmptyState(
              title: 'Report belum tersedia',
              message: 'Pastikan permission Query Report ERPNext aktif.',
            )
          : Column(
              children: [
                for (final row in rows)
                  _AmountRow(label: row.label, amount: row.value),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color color;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.color = _financeGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _financeCardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FinanceIconBox(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final VoidCallback? onTap;

  const _AmountRow({required this.label, required this.amount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (amount < 0 ? _financeOrange : _financeMint).withValues(
                  alpha: amount < 0 ? 0.14 : 1,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: amount < 0
                      ? _financeOrange.withValues(alpha: 0.25)
                      : _financeGreen.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                'Rp ${formatErpCurrency(amount.abs())}',
                style: TextStyle(
                  color: amount < 0 ? _financeOrange : _financeGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final FinanceDocumentRow row;
  final String doctype;

  const _DocumentRow({required this.row, this.doctype = ''});

  @override
  Widget build(BuildContext context) {
    return _SimpleRow(
      title: row.title,
      subtitle: '${row.id} - ${row.date}',
      trailing: row.status,
      amount: row.amount,
      onTap: () => _showFinanceDocumentDetail(context, row, doctype: doctype),
    );
  }
}

class _BankBalanceRow extends StatelessWidget {
  final FinanceBankBalance row;

  const _BankBalanceRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return _SimpleRow(
      title: row.account,
      subtitle: 'Bank Account',
      trailing: 'Balance',
      amount: row.balance,
      onTap: () => _showBankBalance(context, row),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final GeneralLedgerRow row;

  const _LedgerRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return _SimpleRow(
      title: row.account,
      subtitle: [
        row.date,
        if (row.party.trim().isNotEmpty) row.party,
      ].join(' - '),
      trailing: row.debit > 0 ? 'Debit' : 'Credit',
      amount: row.debit > 0 ? row.debit : row.credit,
      onTap: () => _showLedgerDetail(context, row),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;
  final double amount;
  final VoidCallback? onTap;

  const _SimpleRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.amount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _FinanceIconBox(
              icon: Icons.receipt_long_rounded,
              color: amount < 0 ? _financeOrange : _financeBlue,
              size: 40,
              iconSize: 19,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Rp ${formatErpCurrency(amount.abs())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _financeGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
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

void _showFinanceDocumentDetail(
  BuildContext context,
  FinanceDocumentRow row, {
  String doctype = '',
}) {
  showErpDetailSheet(
    context: context,
    title: row.id,
    subtitle: row.title,
    statusText: row.status.isEmpty
        ? (doctype.isEmpty ? 'Document' : doctype)
        : row.status,
    rows: [
      ErpDetailRow(label: 'Document', value: row.id),
      ErpDetailRow(label: 'Title', value: row.title),
      if (doctype.isNotEmpty) ErpDetailRow(label: 'Type', value: doctype),
      if (row.date.isNotEmpty) ErpDetailRow(label: 'Date', value: row.date),
      ErpDetailRow(
        label: 'Amount',
        value: 'Rp ${formatErpCurrency(row.amount.abs())}',
      ),
    ],
  );
}

void _showLedgerDetail(BuildContext context, GeneralLedgerRow row) {
  showErpDetailSheet(
    context: context,
    title: row.account,
    subtitle: row.id,
    statusText: row.debit > 0 ? 'Debit' : 'Credit',
    rows: [
      ErpDetailRow(label: 'GL Entry', value: row.id),
      ErpDetailRow(label: 'Account', value: row.account),
      if (row.party.isNotEmpty) ErpDetailRow(label: 'Party', value: row.party),
      ErpDetailRow(label: 'Date', value: row.date),
      ErpDetailRow(
        label: 'Debit',
        value: 'Rp ${formatErpCurrency(row.debit.abs())}',
      ),
      ErpDetailRow(
        label: 'Credit',
        value: 'Rp ${formatErpCurrency(row.credit.abs())}',
      ),
    ],
  );
}

class _FinanceIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const _FinanceIconBox({
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

BoxDecoration _financeCardDecoration({double radius = 24}) {
  return BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
    boxShadow: [
      BoxShadow(
        color: AppColors.primaryDark.withValues(alpha: 0.055),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ],
  );
}
