import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_status_badge.dart';
import '../../../widgets/responsive/responsive_layout.dart';

class BuyingDetailMetric {
  final String label;
  final String value;
  final IconData icon;

  const BuyingDetailMetric({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class BuyingDetailInfo {
  final String label;
  final String value;

  const BuyingDetailInfo({required this.label, required this.value});
}

class BuyingDetailItem {
  final String title;
  final String subtitle;
  final String qty;
  final String rate;
  final String amount;
  final String note;

  const BuyingDetailItem({
    required this.title,
    this.subtitle = '',
    this.qty = '',
    this.rate = '',
    this.amount = '',
    this.note = '',
  });
}

void showBuyingDocumentDetailSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String statusText,
  required IconData icon,
  required List<BuyingDetailMetric> metrics,
  List<BuyingDetailInfo> infos = const [],
  List<BuyingDetailItem> items = const [],
  Widget? footer,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return TmsxResponsiveBody(
            maxWidth: 680,
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: TmsxResponsive.pagePadding(
                  context,
                  top: 10,
                  bottom: 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    _BuyingDetailHeader(
                      title: title,
                      subtitle: subtitle,
                      statusText: statusText,
                      icon: icon,
                      onClose: () => Navigator.pop(sheetContext),
                    ),
                    if (metrics.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _BuyingMetricGrid(metrics: metrics),
                    ],
                    if (infos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _BuyingInfoCard(infos: infos),
                    ],
                    const SizedBox(height: 14),
                    _BuyingItemsSection(items: items),
                    if (footer != null) ...[const SizedBox(height: 16), footer],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _BuyingDetailHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String statusText;
  final IconData icon;
  final VoidCallback onClose;

  const _BuyingDetailHeader({
    required this.title,
    required this.subtitle,
    required this.statusText,
    required this.icon,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ErpStatusBadge(statusText: statusText),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.slate,
            tooltip: 'Tutup',
          ),
        ],
      ),
    );
  }
}

class _BuyingMetricGrid extends StatelessWidget {
  final List<BuyingDetailMetric> metrics;

  const _BuyingMetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics.map((metric) {
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 40) / 2,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(metric.icon, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metric.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
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
      }).toList(),
    );
  }
}

class _BuyingInfoCard extends StatelessWidget {
  final List<BuyingDetailInfo> infos;

  const _BuyingInfoCard({required this.infos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: infos
            .map(
              (info) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        info.label,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        info.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _BuyingItemsSection extends StatelessWidget {
  final List<BuyingDetailItem> items;

  const _BuyingItemsSection({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.slate),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Item belum tersedia pada detail dokumen.',
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Detail Item',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${items.length} item',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...items.map(_BuyingItemCard.new),
      ],
    );
  }
}

class _BuyingItemCard extends StatelessWidget {
  final BuyingDetailItem item;

  const _BuyingItemCard(this.item);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (item.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ItemStat(label: 'Qty', value: item.qty),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ItemStat(label: 'Rate', value: item.rate),
              ),
            ],
          ),
          if (item.amount.isNotEmpty || item.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.amount.isNotEmpty)
                  Expanded(
                    child: _ItemStat(label: 'Amount', value: item.amount),
                  ),
                if (item.amount.isNotEmpty && item.note.isNotEmpty)
                  const SizedBox(width: 8),
                if (item.note.isNotEmpty)
                  Expanded(
                    child: _ItemStat(label: 'Info', value: item.note),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemStat extends StatelessWidget {
  final String label;
  final String value;

  const _ItemStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '-' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
