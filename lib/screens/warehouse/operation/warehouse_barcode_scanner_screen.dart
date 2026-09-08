import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../models/inventory_item.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseBarcodeScannerScreen extends StatefulWidget {
  const WarehouseBarcodeScannerScreen({super.key});

  @override
  State<WarehouseBarcodeScannerScreen> createState() =>
      _WarehouseBarcodeScannerScreenState();
}

class _WarehouseBarcodeScannerScreenState
    extends State<WarehouseBarcodeScannerScreen> {
  final _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 800,
  );
  final _manualCode = TextEditingController();
  String? _scannedCode;
  List<InventoryItem> _matches = const [];
  bool _loading = true;
  bool _scanLocked = false;
  bool _scannerStarted = false;
  bool _scannerStarting = true;
  String? _error;
  String? _scannerErrorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInventory();
      _startScanner();
    });
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    _manualCode.dispose();
    super.dispose();
  }

  Future<void> _startScanner() async {
    if (!mounted || _scannerStarted) return;
    setState(() {
      _scannerStarting = true;
      _scannerErrorText = null;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _controller.start();
      if (!mounted) return;
      setState(() {
        _scannerStarted = true;
        _scannerStarting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scannerStarted = false;
        _scannerStarting = false;
        _scannerErrorText = _friendlyError(error);
      });
    }
  }

  Future<void> _loadInventory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      if (state.inventory.isEmpty) await state.refreshInventory();
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanLocked || _scannedCode != null) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _scanLocked = true;
      await _findCode(value);
      break;
    }
  }

  Future<void> _findCode(String value) async {
    if (!mounted) return;
    final normalized = value.trim().toLowerCase();
    final inventory = context.read<WarehouseStockState>().inventory;
    setState(() {
      _scannedCode = value.trim();
      _manualCode.text = value.trim();
      _matches =
          inventory
              .where(
                (item) =>
                    item.sku.toLowerCase() == normalized ||
                    item.name.toLowerCase() == normalized,
              )
              .toList()
            ..sort((a, b) => a.warehouseId.compareTo(b.warehouseId));
    });
  }

  Future<void> _scanAgain() async {
    setState(() {
      _scannedCode = null;
      _matches = const [];
      _error = null;
      _scanLocked = false;
    });
    await _startScanner();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Barcode / QR Scan',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
      ),
    ),
    body: RefreshIndicator(
      onRefresh: _loadInventory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          const WarehouseSectionHeader(
            title: 'Scan Item',
            subtitle: 'Arahkan kamera ke barcode atau QR kode item',
            icon: Icons.qr_code_scanner_rounded,
          ),
          warehouseSectionGap,
          _scannerPanel(),
          const SizedBox(height: 12),
          _manualInput(),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            WarehouseInfoPanel(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              message: _error!,
            ),
          ],
          if (_scannedCode != null) ...[
            warehouseSectionGap,
            WarehouseSectionHeader(
              title: 'Hasil Scan',
              subtitle: 'Kode: $_scannedCode',
              icon: Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 12),
            if (_matches.isEmpty)
              const WarehouseInfoPanel(
                icon: Icons.search_off_rounded,
                color: AppColors.warning,
                message:
                    'Item tidak ditemukan. Pastikan barcode atau QR berisi kode item yang benar.',
              )
            else ...[
              _summaryCard(),
              const SizedBox(height: 10),
              ..._matches.map(_stockCard),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _scanAgain,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan item lain'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _scannerPanel() => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _scannerError(error),
            placeholderBuilder: (context) => _scannerPlaceholder(),
          ),
          if (_scannerStarting || _scannerErrorText != null)
            _scannerStatusOverlay(),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 220,
                height: 130,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.white, width: 3),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: IconButton.filled(
              tooltip: 'Nyalakan atau matikan flash',
              onPressed: _toggleTorch,
              icon: const Icon(Icons.flashlight_on_rounded),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _toggleTorch() async {
    try {
      if (!_scannerStarted) {
        await _startScanner();
      }
      await _controller.toggleTorch();
    } catch (error) {
      if (!mounted) return;
      setState(() => _scannerErrorText = _friendlyError(error));
    }
  }

  Widget _scannerPlaceholder() => const ColoredBox(
    color: AppColors.primaryDark,
    child: Center(child: CircularProgressIndicator(color: AppColors.white)),
  );

  Widget _scannerStatusOverlay() => ColoredBox(
    color: AppColors.primaryDark,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _scannerErrorText == null
                ? Icons.qr_code_scanner_rounded
                : Icons.no_photography_outlined,
            color: AppColors.white,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            _scannerErrorText == null
                ? 'Menyiapkan kamera scanner'
                : 'Kamera scanner belum bisa dibuka',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (_scannerErrorText != null) ...[
            const SizedBox(height: 6),
            Text(
              _scannerErrorText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.white),
              ),
              onPressed: _startScanner,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba buka kamera lagi'),
            ),
          ] else ...[
            const SizedBox(height: 14),
            const CircularProgressIndicator(color: AppColors.white),
          ],
        ],
      ),
    ),
  );

  Widget _scannerError(MobileScannerException error) => ColoredBox(
    color: AppColors.primaryDark,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: AppColors.white,
            size: 42,
          ),
          const SizedBox(height: 12),
          const Text(
            'Kamera scanner belum bisa dibuka',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _friendlyError(error),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _manualInput() => Row(
    children: [
      Expanded(
        child: WarehouseSearchField(
          controller: _manualCode,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) _findCode(value);
          },
          hintText: 'Masukkan item code manual',
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        tooltip: 'Cari item',
        onPressed: () {
          if (_manualCode.text.trim().isNotEmpty) {
            _findCode(_manualCode.text);
          }
        },
        icon: const Icon(Icons.search_rounded),
      ),
    ],
  );

  Widget _summaryCard() {
    final totalStock = _matches.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.primary,
            child: Icon(Icons.check_rounded),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _matches.first.name,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_matches.first.sku} | Total stok $totalStock',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
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

  Widget _stockCard(InventoryItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.softGreen,
            foregroundColor: AppColors.primary,
            child: Icon(Icons.warehouse_outlined),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              item.warehouseId,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${item.quantity}',
            style: TextStyle(
              color: item.quantity > 0 ? AppColors.success : AppColors.danger,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
