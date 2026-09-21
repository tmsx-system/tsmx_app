import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_format.dart';
import 'erp_status_badge.dart';

class ErpDocumentCard extends StatelessWidget {
  final String id;
  final String party;
  final String statusText;
  final String date;
  final double value;
  final String? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDownload;
  final VoidCallback? onPrint;
  final VoidCallback? onDelete;

  const ErpDocumentCard({
    super.key,
    required this.id,
    required this.party,
    required this.statusText,
    required this.date,
    required this.value,
    this.trailing,
    this.onTap,
    this.onEdit,
    this.onDuplicate,
    this.onDownload,
    this.onPrint,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final formattedValue = 'Rp ${formatErpCurrency(value)}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: AppColors.primary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'HankenGrotesk',
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          party.trim().isEmpty ? '-' : party,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.slate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ErpStatusBadge(statusText: statusText),
                      if (onEdit != null ||
                          onDuplicate != null ||
                          onPrint != null ||
                          onDownload != null ||
                          onDelete != null) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: PopupMenuButton<String>(
                            tooltip: 'Actions',
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            color: AppColors.white,
                            icon: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.more_horiz_rounded,
                                color: AppColors.slate,
                                size: 19,
                              ),
                            ),
                            onSelected: (value) {
                              if (value == 'edit') onEdit?.call();
                              if (value == 'duplicate') onDuplicate?.call();
                              if (value == 'print') onPrint?.call();
                              if (value == 'download') onDownload?.call();
                              if (value == 'delete') onDelete?.call();
                            },
                            itemBuilder: (context) => [
                              if (onEdit != null)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                              if (onDuplicate != null)
                                const PopupMenuItem(
                                  value: 'duplicate',
                                  child: Row(
                                    children: [
                                      Icon(Icons.copy_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('Duplicate'),
                                    ],
                                  ),
                                ),
                              if (onPrint != null)
                                const PopupMenuItem(
                                  value: 'print',
                                  child: Row(
                                    children: [
                                      Icon(Icons.print_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Print'),
                                    ],
                                  ),
                                ),
                              if (onDownload != null)
                                const PopupMenuItem(
                                  value: 'download',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Download PDF'),
                                    ],
                                  ),
                                ),
                              if (onDelete != null)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _InfoPill(
                    icon: Icons.calendar_month_outlined,
                    label: date.isEmpty ? '-' : date,
                  ),
                  _InfoPill(
                    icon: Icons.payments_outlined,
                    label: formattedValue,
                    strong: true,
                  ),
                ],
              ),
              if (trailing != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    trailing!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool strong;

  const _InfoPill({
    required this.icon,
    required this.label,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: strong ? AppColors.softGreen : AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: strong
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: strong ? AppColors.primary : AppColors.slate,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: strong ? 12 : 10,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: strong ? AppColors.primary : AppColors.slate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
