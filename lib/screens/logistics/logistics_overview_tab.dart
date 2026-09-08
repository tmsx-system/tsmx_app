import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery_note.dart';
import '../../state/logistics/logistics_overview_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_format.dart';
import 'logistics_widgets.dart';

class LogisticsOverviewTab extends StatelessWidget {
  final ValueChanged<int> onMenuSelected;

  const LogisticsOverviewTab({super.key, required this.onMenuSelected});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LogisticsOverviewState>();
    final docs = state.deliveryNotes;
    final outstandingRows = docs.where(_isOutstanding).toList();
    final completed = docs
        .where((doc) => doc.statusKey == DeliveryNoteStatusKey.completed)
        .length;
    final draft = docs.where((doc) => doc.docStatus == 0).length;
    final submitted = docs.where((doc) {
      return doc.docStatus == 1 &&
          doc.statusKey != DeliveryNoteStatusKey.completed &&
          doc.statusKey != DeliveryNoteStatusKey.cancelled &&
          doc.statusKey != DeliveryNoteStatusKey.closed;
    }).length;
    final outstandingValue = outstandingRows.fold<double>(
      0,
      (total, doc) => total + doc.value,
    );

    return RefreshIndicator(
      onRefresh: () =>
          context.read<LogisticsOverviewState>().refreshDeliveryNotes(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: logisticsPagePaddingOf(context),
        children: [
          const LogisticsSectionHeader(
            title: 'Dashboard Logistics',
            subtitle: 'Pantau pengiriman, armada, dan bukti customer',
            icon: Icons.local_shipping_rounded,
          ),
          if (state.isDeliveryNotesLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (state.deliveryNotesError != null) ...[
            const SizedBox(height: 12),
            LogisticsInfoPanel(
              message: state.deliveryNotesError!,
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
            ),
          ],
          logisticsSectionGap,
          LogisticsHeroSummaryCard(
            title: 'Prioritas Pengiriman',
            subtitle: 'Pantau outstanding dan bukti customer',
            icon: Icons.delivery_dining_rounded,
            stats: [
              LogisticsHeroStat(
                label: 'Outstanding',
                value: '${outstandingRows.length}',
              ),
              LogisticsHeroStat(label: 'Completed', value: '$completed'),
              LogisticsHeroStat(
                label: 'Nilai',
                value: 'Rp ${formatErpCurrency(outstandingValue)}',
                compact: true,
              ),
            ],
            onTap: () => onMenuSelected(2),
          ),
          logisticsSectionGap,
          LogisticsMetricGrid(
            items: [
              LogisticsMetricItem(
                label: 'Submitted',
                value: '$submitted',
                icon: Icons.local_shipping_outlined,
                color: AppColors.primary,
              ),
              LogisticsMetricItem(
                label: 'Draft',
                value: '$draft',
                icon: Icons.edit_note_rounded,
                color: AppColors.slate,
              ),
            ],
          ),
          logisticsSectionGap,
          const LogisticsSectionHeader(
            title: 'Ringkasan Kerja',
            subtitle: 'Prioritas yang perlu dicek hari ini',
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: 12),
          _LogisticsWorkSummary(
            outstanding: outstandingRows.length,
            submitted: submitted,
            draft: draft,
            completed: completed,
          ),
        ],
      ),
    );
  }

  static bool _isOutstanding(DeliveryNote doc) {
    return doc.statusKey != DeliveryNoteStatusKey.completed &&
        doc.statusKey != DeliveryNoteStatusKey.cancelled &&
        doc.statusKey != DeliveryNoteStatusKey.closed;
  }
}

class _LogisticsWorkSummary extends StatelessWidget {
  final int outstanding;
  final int submitted;
  final int draft;
  final int completed;

  const _LogisticsWorkSummary({
    required this.outstanding,
    required this.submitted,
    required this.draft,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
      boxShadow: AppColors.cardShadow,
    ),
    child: Column(
      children: [
        _summaryRow(
          icon: Icons.priority_high_rounded,
          label: 'Outstanding delivery',
          value: '$outstanding',
          color: outstanding > 0 ? AppColors.warning : AppColors.success,
        ),
        const Divider(height: 18),
        _summaryRow(
          icon: Icons.local_shipping_outlined,
          label: 'Pengiriman diproses',
          value: '$submitted',
          color: AppColors.primary,
        ),
        const Divider(height: 18),
        _summaryRow(
          icon: Icons.edit_note_rounded,
          label: 'Draft belum diproses',
          value: '$draft',
          color: AppColors.slate,
        ),
        const Divider(height: 18),
        _summaryRow(
          icon: Icons.task_alt_rounded,
          label: 'Pengiriman selesai',
          value: '$completed',
          color: AppColors.success,
        ),
      ],
    ),
  );

  static Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) => Row(
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        child: Icon(icon, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}
