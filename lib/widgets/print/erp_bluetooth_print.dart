import 'dart:typed_data';

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
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Mengunduh print format...',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final pdfBytes = Uint8List.fromList(await downloadPdf());
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrintPreviewScreen(
            title: title,
            pdfBytes: pdfBytes,
            printerName: printer!.name,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
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
