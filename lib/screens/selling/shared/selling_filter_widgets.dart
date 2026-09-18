import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/responsive/responsive_layout.dart';

enum SellingSortOption { newest, oldest, valueHigh, valueLow }

enum SellingDocStatusFilter { all, draft, submitted, cancelled }

class SellingAdvancedFilters {
  final String customer;
  final double? minValue;
  final double? maxValue;
  final DateTime? from;
  final DateTime? to;
  final SellingDocStatusFilter docStatus;

  const SellingAdvancedFilters({
    required this.customer,
    required this.minValue,
    required this.maxValue,
    required this.from,
    required this.to,
    required this.docStatus,
  });

  static const empty = SellingAdvancedFilters(
    customer: '',
    minValue: null,
    maxValue: null,
    from: null,
    to: null,
    docStatus: SellingDocStatusFilter.all,
  );
}

class SellingQuickFilters extends StatelessWidget {
  final SellingSortOption sortOption;
  final String Function(SellingSortOption) sortLabel;
  final ValueChanged<SellingSortOption> onSortChanged;
  final VoidCallback onReset;
  final int advancedCount;
  final VoidCallback onAdvancedFilters;

  const SellingQuickFilters({
    super.key,
    required this.sortOption,
    required this.sortLabel,
    required this.onSortChanged,
    required this.onReset,
    required this.advancedCount,
    required this.onAdvancedFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<SellingSortOption>(
              initialValue: sortOption,
              decoration: InputDecoration(
                labelText: 'Urutkan',
                prefixIcon: const Icon(Icons.sort_rounded, size: 18),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.30),
                  ),
                ),
              ),
              items: SellingSortOption.values.map((option) {
                return DropdownMenuItem<SellingSortOption>(
                  value: option,
                  child: Text(
                    sortLabel(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (option) {
                if (option != null) onSortChanged(option);
              },
            ),
          ),
          const SizedBox(width: 8),
          _SellingFilterButton(
            icon: Icons.tune_rounded,
            label: advancedCount > 0 ? 'Filter $advancedCount' : 'Filter',
            color: AppColors.primary,
            onTap: onAdvancedFilters,
          ),
          const SizedBox(width: 8),
          _SellingFilterButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reset',
            color: const Color(0xFF2563EB),
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

class _SellingFilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _SellingFilterButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 68,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SellingAdvancedFilterSheet extends StatefulWidget {
  final String title;
  final SellingAdvancedFilters initial;

  const SellingAdvancedFilterSheet({
    super.key,
    required this.title,
    required this.initial,
  });

  @override
  State<SellingAdvancedFilterSheet> createState() =>
      _SellingAdvancedFilterSheetState();
}

class _SellingAdvancedFilterSheetState
    extends State<SellingAdvancedFilterSheet> {
  late final TextEditingController _customerCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  DateTime? _from;
  DateTime? _to;
  late SellingDocStatusFilter _docStatus;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController(text: widget.initial.customer);
    _minCtrl = TextEditingController(
      text: widget.initial.minValue?.toStringAsFixed(0) ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.initial.maxValue?.toStringAsFixed(0) ?? '',
    );
    _from = widget.initial.from;
    _to = widget.initial.to;
    _docStatus = widget.initial.docStatus;
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  String _dateText(DateTime? date) {
    if (date == null) return 'Any';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      SellingAdvancedFilters(
        customer: _customerCtrl.text.trim(),
        minValue: double.tryParse(_minCtrl.text.trim()),
        maxValue: double.tryParse(_maxCtrl.text.trim()),
        from: _from,
        to: _to,
        docStatus: _docStatus,
      ),
    );
  }

  void _reset() {
    Navigator.pop(context, SellingAdvancedFilters.empty);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: TmsxResponsiveBody(
        maxWidth: 560,
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: TmsxResponsive.horizontalPadding(context),
            right: TmsxResponsive.horizontalPadding(context),
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _customerCtrl,
                  decoration: const InputDecoration(labelText: 'Customer'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min value',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max value',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: true),
                        icon: const Icon(Icons.date_range_rounded),
                        label: Text('From ${_dateText(_from)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: false),
                        icon: const Icon(Icons.event_rounded),
                        label: Text('To ${_dateText(_to)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<SellingDocStatusFilter>(
                  initialValue: _docStatus,
                  decoration: const InputDecoration(labelText: 'Doc status'),
                  items: const [
                    DropdownMenuItem(
                      value: SellingDocStatusFilter.all,
                      child: Text('All'),
                    ),
                    DropdownMenuItem(
                      value: SellingDocStatusFilter.draft,
                      child: Text('Draft'),
                    ),
                    DropdownMenuItem(
                      value: SellingDocStatusFilter.submitted,
                      child: Text('Submitted'),
                    ),
                    DropdownMenuItem(
                      value: SellingDocStatusFilter.cancelled,
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _docStatus = value);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _apply,
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
