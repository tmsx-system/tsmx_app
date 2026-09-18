import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/pos/pos_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_format.dart';

class PosOverviewTab extends StatelessWidget {
  final ValueChanged<int> onMenuSelected;
  final List<PosOverviewAction> actions;

  const PosOverviewTab({
    super.key,
    required this.onMenuSelected,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosState>();
    final openSessions = state.openings.where((row) => row.docStatus == 1).length;
    final invoiceCount = state.invoices.length;
    final invoiceTotal = state.invoices.fold<double>(
      0,
      (sum, row) => sum + row.value,
    );
    final closingCount = state.closings.length;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await Future.wait([
          state.refreshProfiles(),
          state.refreshOpenings(),
          state.refreshInvoices(),
          state.refreshClosings(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 104),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POS Workspace',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Alur : Profile → Opening → Invoice → Closing',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MetricChip(
                      label: 'Profiles',
                      value: '${state.profiles.length}',
                      color: const Color(0xFF0F766E),
                    ),
                    _MetricChip(
                      label: 'Open Sessions',
                      value: '$openSessions',
                      color: const Color(0xFF16A34A),
                    ),
                    _MetricChip(
                      label: 'Invoices',
                      value: '$invoiceCount',
                      color: const Color(0xFFF59E0B),
                    ),
                    _MetricChip(
                      label: 'Closings',
                      value: '$closingCount',
                      color: const Color(0xFF7C3AED),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Total Invoice: Rp ${formatErpCurrency(invoiceTotal)}',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              itemBuilder: (context, index) {
                final action = actions[index];
                return Material(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: action.onTap,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: action.color.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(action.icon, color: action.color),
                          const Spacer(),
                          Text(
                            action.label,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class PosOverviewAction {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const PosOverviewAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
