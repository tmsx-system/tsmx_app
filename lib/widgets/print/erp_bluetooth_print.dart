import 'package:flutter/material.dart';

import '../../screens/settings/bluetooth_printer_screen.dart';
import '../../screens/settings/print_preview_screen.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../theme/app_colors.dart';

Future<void> printErpPdfViaBluetooth(
  BuildContext context, {
  required Future<List<int>> Function() downloadPdf,
  required String title,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    var printer = await BluetoothPrinterService.savedPrinter();
    if (printer == null) {
      if (!context.mounted) return;
      printer = await showBluetoothPrinterPicker(context);
      if (printer == null) {
        throw Exception('Pilih printer Bluetooth dulu, lalu tekan Print lagi.');
      }
    }

    if (!context.mounted) return;
    final status = ValueNotifier<String>('Mengunduh PDF...');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, message, __) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    try {
      final pdfBytes = await downloadPdf();
      status.value = 'Merender struk...';
      final pages = await BluetoothPrinterService.prepareReceiptImages(pdfBytes);
      if (!context.mounted) {
        status.dispose();
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      await Future<void>.delayed(Duration.zero);
      status.dispose();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrintPreviewScreen(
            title: title,
            pages: pages,
            printerName: printer!.name,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await Future<void>.delayed(Duration.zero);
      }
      status.dispose();
      rethrow;
    }
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.danger,
        action: SnackBarAction(
          label: 'Printer',
          textColor: AppColors.white,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BluetoothPrinterScreen()),
            );
          },
        ),
      ),
    );
  }
}
