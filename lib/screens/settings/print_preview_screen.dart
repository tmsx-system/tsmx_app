import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/bluetooth_printer_service.dart';
import '../../theme/app_colors.dart';
import 'bluetooth_printer_screen.dart';

/// Width of the 58 mm receipt strip on screen.
///
/// The bitmap is already cropped to the printable strip. This only chooses how
/// large that strip is drawn so it stays readable on a phone, tablet, or laptop.
double receiptPreviewWidth(double viewportWidth) {
  final available = math.max(0.0, viewportWidth - 32);
  if (available <= 520) return math.min(available, 420);
  if (available <= 900) return math.min(available * 0.62, 460);
  return math.min(available * 0.38, 480);
}

class PrintPreviewScreen extends StatefulWidget {
  final String title;
  final Uint8List pdfBytes;
  final String? printerName;

  const PrintPreviewScreen({
    super.key,
    required this.title,
    required this.pdfBytes,
    this.printerName,
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
    final pages = _printPages;
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
              'Tampilan kertas 58 mm.',
              style: TextStyle(
                color: AppColors.slate.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: pages == null
                ? Center(
                    child: preparing
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _prepError
                                      .toString()
                                      .replaceFirst('Exception: ', ''),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  )
                : _ReceiptStrip(pages: pages),
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
                        : widget.printerName == null
                        ? 'Belum ada printer. Preview tetap bisa dilihat.'
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

class _ReceiptStrip extends StatelessWidget {
  final List<Uint8List> pages;

  const _ReceiptStrip({required this.pages});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = receiptPreviewWidth(constraints.maxWidth);
        return ListView(
          scrollDirection: Axis.vertical,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            for (var i = 0; i < pages.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == pages.length - 1 ? 0 : 12,
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        pages[i],
                        width: width,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
