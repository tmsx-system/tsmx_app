import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_doc_utils.dart';
import 'erp_detail_sheet.dart';
import 'erp_error_dialog.dart';

Future<bool> runErpWorkflowAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String successMessage,
}) async {
  try {
    await action();
    if (!context.mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    await showErpError(context, error: e, action: 'menjalankan aksi dokumen');
    return false;
  }
}

Future<bool> confirmErpAction(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok == true;
}

Widget erpActionButton({
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
  bool filled = false,
}) {
  final enabled = onPressed != null;
  final foreground = filled
      ? AppColors.white
      : (enabled ? AppColors.primary : AppColors.slate);
  final background = filled
      ? (enabled ? AppColors.primary : AppColors.surfaceMuted)
      : AppColors.white;
  final borderColor = filled
      ? Colors.transparent
      : (enabled
            ? AppColors.primary.withValues(alpha: 0.26)
            : AppColors.border);

  return Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color:
                          (filled ? AppColors.primary : AppColors.primaryDark)
                              .withValues(alpha: filled ? 0.20 : 0.06),
                      blurRadius: filled ? 18 : 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: filled
                      ? AppColors.white.withValues(alpha: 0.16)
                      : AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: foreground),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget erpWorkflowSection({
  required String title,
  required List<Widget> children,
}) {
  if (children.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.slate,
        ),
      ),
      const SizedBox(height: 8),
      ...children,
    ],
  );
}

List<Widget> erpRelatedDocChips({
  required List<String> docIds,
  required void Function(String id) onTap,
}) {
  if (docIds.isEmpty) return [];
  return [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: docIds.map((id) {
        return ActionChip(
          label: Text(
            id,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          onPressed: () => onTap(id),
        );
      }).toList(),
    ),
  ];
}

ErpDetailRow docStatusRow(int docStatus) =>
    ErpDetailRow(label: 'Doc Status', value: docStatusLabel(docStatus));
