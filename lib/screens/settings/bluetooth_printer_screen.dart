import 'package:flutter/material.dart';

import '../../services/bluetooth_printer_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/erp/erp_error_dialog.dart';

class BluetoothPrinterScreen extends StatefulWidget {
  final bool popOnSelect;

  const BluetoothPrinterScreen({super.key, this.popOnSelect = false});

  @override
  State<BluetoothPrinterScreen> createState() => _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  List<PairedPrinter> _printers = const [];
  PairedPrinter? _saved;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await BluetoothPrinterService.savedPrinter();
      final printers = await BluetoothPrinterService.pairedPrinters();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _printers = printers;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(PairedPrinter printer) async {
    await BluetoothPrinterService.savePrinter(printer);
    try {
      await BluetoothPrinterService.connect(printer.mac);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _saved = printer);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Printer ${printer.name} disimpan.')),
    );
    if (widget.popOnSelect) {
      Navigator.pop(context, printer);
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
          'Printer Bluetooth',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Text(
              'Pair printer di Settings Bluetooth HP (PIN 0000/1234). Status Connected tidak wajib; yang penting sudah Paired. Cetakan memakai kertas 58 mm.',
              style: TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_printers.isEmpty && !_loading)
              const Text(
                'Tidak ada perangkat Bluetooth yang sudah pairing. Pair printer di pengaturan HP, lalu tarik untuk refresh. Emulator tidak bisa membaca printer yang ter-pair di Windows.',
                style: TextStyle(fontWeight: FontWeight.w700),
              )
            else
              ..._printers.map((printer) {
                final selected = _saved?.mac == printer.mac;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Icon(
                        Icons.print_rounded,
                        color: selected ? AppColors.primary : AppColors.slate,
                      ),
                      title: Text(
                        printer.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(printer.mac),
                      trailing: selected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primary,
                            )
                          : null,
                      onTap: () => _select(printer),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

Future<PairedPrinter?> showBluetoothPrinterPicker(BuildContext context) {
  return Navigator.of(context).push<PairedPrinter>(
    MaterialPageRoute(
      builder: (_) => const BluetoothPrinterScreen(popOnSelect: true),
    ),
  );
}
