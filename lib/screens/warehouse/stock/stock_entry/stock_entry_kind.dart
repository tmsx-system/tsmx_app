import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/stock_entry.dart';
import '../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../theme/app_colors.dart';
import '../../shared/warehouse_widgets.dart';

class StockEntryKind {
  final String name;
  final String purpose;

  const StockEntryKind({required this.name, required this.purpose});

  factory StockEntryKind.fromType(StockEntryType type) {
    return StockEntryKind(name: type.name, purpose: type.purpose);
  }

  String get title => name;
  String get stockEntryType => name;
  String get subtitle => 'Purpose: $purpose';

  String get _purposeKey => purpose.trim().toLowerCase();

  bool get needsSource => switch (_purposeKey) {
    'material receipt' || 'manufacture' => false,
    _ => true,
  };

  bool get needsTarget => switch (_purposeKey) {
    'material issue' ||
    'material consumption for manufacture' => false,
    _ => true,
  };

  bool get allowSameWarehouse => switch (_purposeKey) {
    'repack' || 'disassemble' => true,
    _ => false,
  };

  IconData get icon => switch (_purposeKey) {
    'material transfer' => Icons.swap_horiz_rounded,
    'material receipt' => Icons.move_to_inbox_rounded,
    'material issue' => Icons.outbox_rounded,
    'repack' => Icons.inventory_2_outlined,
    'manufacture' => Icons.precision_manufacturing_outlined,
    'material transfer for manufacture' => Icons.factory_outlined,
    'material consumption for manufacture' => Icons.science_outlined,
    'disassemble' => Icons.call_split_rounded,
    'send to subcontractor' => Icons.handshake_outlined,
    _ => Icons.inventory_2_outlined,
  };

  Color get color => switch (_purposeKey) {
    'material transfer' || 'material transfer for manufacture' => warehouseOrange,
    'material receipt' => warehouseGreen,
    'material issue' ||
    'material consumption for manufacture' => warehouseCyan,
    'repack' => warehousePurple,
    _ => warehouseBlue,
  };

  String get instruction =>
      'Tipe $name (purpose $purpose) diambil dari ERPNext dan sudah dikunci di form ini.';
}

Future<StockEntryKind?> showStockEntryTypePicker(BuildContext context) {
  final state = context.read<WarehouseStockState>();
  return showModalBottomSheet<StockEntryKind>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return ChangeNotifierProvider.value(
        value: state,
        child: const _StockEntryTypePickerSheet(),
      );
    },
  );
}

class _StockEntryTypePickerSheet extends StatefulWidget {
  const _StockEntryTypePickerSheet();

  @override
  State<_StockEntryTypePickerSheet> createState() =>
      _StockEntryTypePickerSheetState();
}

class _StockEntryTypePickerSheetState extends State<_StockEntryTypePickerSheet> {
  bool _loading = true;
  String? _error;
  List<StockEntryKind> _types = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context.read<WarehouseStockState>().fetchStockEntryTypes(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _types = rows.map(StockEntryKind.fromType).toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pilih tipe Stock Entry',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang',
                    onPressed: _loading
                        ? null
                        : () => _load(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Daftar diambil dari doctype Stock Entry Type.',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: LinearProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _load(forceRefresh: true),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              )
            else if (_types.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Text(
                  'Tidak ada Stock Entry Type yang bisa dibaca.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: _types.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final kind = _types[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: kind.color,
                        foregroundColor: Colors.white,
                        child: Icon(kind.icon, size: 20),
                      ),
                      title: Text(
                        kind.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        kind.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, kind),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
