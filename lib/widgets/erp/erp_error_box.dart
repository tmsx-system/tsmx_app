import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ErpErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErpErrorBox({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mohon maaf, data belum bisa ditampilkan',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Coba lagi',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.danger,
            ),
          ],
        ],
      ),
    );
  }
}
