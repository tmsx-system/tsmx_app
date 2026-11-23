import 'package:flutter/material.dart';

import '../../../../../models/stock_opname.dart';
import '../../../../../theme/app_colors.dart';

class StockAwalHighlight extends StatelessWidget {
  final double qty;
  final String uom;

  const StockAwalHighlight({super.key, required this.qty, required this.uom});

  @override
  Widget build(BuildContext context) {
    final unit = uom.trim();
    final amount = unit.isEmpty
        ? formatStockQty(qty)
        : '${formatStockQty(qty)} $unit';
    return Text(
      'Stock awal $amount',
      style: const TextStyle(
        color: Color(0xFF15803D),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class StockOpnameMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const StockOpnameMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
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
                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
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
