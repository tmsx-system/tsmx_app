import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/bluetooth_printer_service.dart';
import '../../theme/app_colors.dart';
import 'bluetooth_printer_screen.dart';

class PrintPreviewScreen extends StatefulWidget {
  final String title;
  final Uint8List pdfBytes;
  final String printerName;

  const PrintPreviewScreen({
    super.key,
    required this.title,
    required this.pdfBytes,
    required this.printerName,
  });

  @override
  State<PrintPreviewScreen> createState() => _PrintPreviewScreenState();
}

class _PrintPreviewScreenState extends State<PrintPreviewScreen> {
  bool _printing = false;
  List<Uint8List>? _printPages;
  Object? _prepError;

  @override
  void initState() {
    super.initState();
    _preparePrintData();
  }

  Future<void> _preparePrintData() async {
    try {
      final pages = await BluetoothPrinterService.preparePrintImages(
        widget.pdfBytes,
      );
      if (!mounted) return;
      setState(() {
        _printPages = pages;
        _prepError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _prepError = error);
    }
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      var pages = _printPages;
      pages ??= await BluetoothPrinterService.preparePrintImages(
        widget.pdfBytes,
      );
      if (!mounted) return;
      _printPages = pages;
      await BluetoothPrinterService.printReceiptImages(pages);
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
    final preparing = _printPages == null && _prepError == null;
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
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Tampilan print format ERPNext. Ketuk dua kali untuk zoom, cubit untuk perbesar.',
              style: TextStyle(
                color: AppColors.slate.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) async => widget.pdfBytes,
              maxPageWidth: 420,
              useActions: false,
              allowPrinting: false,
              allowSharing: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              dynamicLayout: false,
              padding: EdgeInsets.zero,
              scrollViewDecoration: const BoxDecoration(
                color: AppColors.background,
              ),
              pdfPreviewPageDecoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppColors.cardShadow,
              ),
              loadingWidget: const Center(child: CircularProgressIndicator()),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    preparing
                        ? 'Menyiapkan data cetak 58 mm...'
                        : 'Printer: ${widget.printerName}',
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
