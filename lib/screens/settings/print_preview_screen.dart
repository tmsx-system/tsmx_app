import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/bluetooth_printer_service.dart';
import '../../theme/app_colors.dart';
import 'bluetooth_printer_screen.dart';

class PrintPreviewScreen extends StatefulWidget {
  final String title;
  final List<ReceiptPage> pages;
  final String printerName;

  const PrintPreviewScreen({
    super.key,
    required this.title,
    required this.pages,
    required this.printerName,
  });

  @override
  State<PrintPreviewScreen> createState() => _PrintPreviewScreenState();
}

class _PrintPreviewScreenState extends State<PrintPreviewScreen> {
  bool _printing = false;
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await BluetoothPrinterService.printReceiptImages(widget.pages);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} berhasil dicetak.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.danger,
          action: SnackBarAction(
            label: 'Printer',
            textColor: AppColors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BluetoothPrinterScreen(),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Preview Struk',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset zoom',
            onPressed: () => _transform.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Cubit untuk zoom. Tampilan preview memakai resolusi tinggi; cetak tetap 58 mm.',
              style: TextStyle(
                color: AppColors.slate.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.6,
                  maxScale: 6,
                  boundaryMargin: const EdgeInsets.all(120),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final page in widget.pages)
                            Container(
                              width: math.min(380, constraints.maxWidth - 32),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppColors.cardShadow,
                              ),
                              child: Image.memory(
                                page.previewPng,
                                fit: BoxFit.fitWidth,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Printer: ${widget.printerName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _printing ? null : _print,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: Icon(
                      _printing
                          ? Icons.hourglass_top_rounded
                          : Icons.print_rounded,
                    ),
                    label: Text(
                      _printing ? 'Mencetak...' : 'Print',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
