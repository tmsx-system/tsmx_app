import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_colors.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../models/warehouse_info.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';

class CreateStockEntryScreen extends StatefulWidget {
  const CreateStockEntryScreen({super.key});

  @override
  State<CreateStockEntryScreen> createState() => _CreateStockEntryScreenState();
}

class _CreateStockEntryScreenState extends State<CreateStockEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  final DateTime _postingDate = DateTime.now();

  List<WarehouseInfo> _warehouses = [];
  List<ErpItemOption> _items = [];
  String? _selectedItem;
  String? _selectedWarehouse;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final appState = context.read<WarehouseStockState>();
    if (appState.warehouses.isEmpty) await appState.refreshWarehouses();
    List<Map<String, dynamic>> rows;
    try {
      rows = await appState.frappeService.fetchResource(
        'Item',
        fields: const ['name', 'item_name'],
        filters: const [
          ['disabled', '=', 0],
        ],
        orderBy: 'item_name asc',
      );
    } catch (_) {
      rows = await appState.frappeService.fetchResource(
        'Item',
        fields: const ['name', 'item_name'],
        orderBy: 'item_name asc',
      );
    }
    setState(() {
      _warehouses = appState.warehouses.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _items = rows
          .map((row) {
            final id = row['name']?.toString() ?? '';
            if (id.isEmpty) return null;
            return ErpItemOption(
              id: id,
              label: row['item_name']?.toString() ?? id,
            );
          })
          .whereType<ErpItemOption>()
          .toList();
      _selectedWarehouse = appState.preferredWarehouse(_warehouses);
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final appState = context.read<WarehouseStockState>();
      final qty = double.parse(_qtyCtrl.text.trim());

      final items = [
        {
          'item_code': _selectedItem,
          'warehouse': _selectedWarehouse,
          'qty': qty,
        },
      ];

      await appState.createStockEntry(
        stockEntryType: 'Stock Reconciliation',
        items: items,
        postingDate: _postingDate,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock Entry dibuat'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat Stock Entry: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        title: const Text(
          'Create Stock Entry',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ErpItemAutocompleteField(
                      label: 'Item',
                      selectedId: _selectedItem,
                      options: _items,
                      decoration: _decoration('Item'),
                      onSelected: (value) =>
                          setState(() => _selectedItem = value),
                      validator: (value) =>
                          value == null ? 'Item wajib diisi' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration('Quantity'),
                      validator: (v) {
                        final q = double.tryParse(v?.trim() ?? '');
                        if (q == null || q <= 0) return 'Qty harus > 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ErpItemAutocompleteField(
                      label: 'Warehouse',
                      selectedId: _selectedWarehouse,
                      options: _warehouses
                          .map(
                            (warehouse) => ErpItemOption(
                              id: warehouse.name,
                              label: warehouse.displayName,
                            ),
                          )
                          .toList(),
                      decoration: _decoration('Warehouse'),
                      onSelected: (value) =>
                          setState(() => _selectedWarehouse = value),
                      validator: (value) =>
                          value == null ? 'Warehouse wajib dipilih' : null,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Create Stock Entry',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
