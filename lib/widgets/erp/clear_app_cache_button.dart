import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/todo/todo_state.dart';
import '../../state/warehouse/warehouse_stock_state.dart';
import '../../theme/app_colors.dart';

class ClearAppCacheButton extends StatefulWidget {
  final bool boxed;

  const ClearAppCacheButton({super.key, this.boxed = true});

  @override
  State<ClearAppCacheButton> createState() => _ClearAppCacheButtonState();
}

class _ClearAppCacheButtonState extends State<ClearAppCacheButton> {
  bool _busy = false;

  Future<void> _confirmAndClear() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'Customer, supplier, gudang, dan data sementara akan di-get ulang. '
          'Anda tetap login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<AppState>().resetLocalAppCache();
      if (!mounted) return;
      await context.read<WarehouseStockState>().invalidateAndRefreshMasters();
      if (!mounted) return;
      if (context.read<AppState>().canUseApprovals) {
        await context.read<TodoState>().fetchApprovalTodos(forceRefresh: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache dibersihkan. Data di-get ulang.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(
            Icons.refresh_rounded,
            color: AppColors.primary,
            size: 22,
          );

    if (!widget.boxed) {
      return IconButton(
        tooltip: 'Clear cache',
        onPressed: _busy ? null : _confirmAndClear,
        icon: icon,
      );
    }

    return Tooltip(
      message: 'Clear cache',
      child: InkWell(
        onTap: _busy ? null : _confirmAndClear,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: icon,
        ),
      ),
    );
  }
}
