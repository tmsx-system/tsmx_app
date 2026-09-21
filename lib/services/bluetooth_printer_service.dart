import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PairedPrinter {
  final String name;
  final String mac;

  const PairedPrinter({required this.name, required this.mac});
}

class ReceiptPage {
  final Uint8List previewPng;
  final Uint8List printPng;

  const ReceiptPage({required this.previewPng, required this.printPng});
}

List<Uint8List>? _fitReceiptIsolate(Uint8List png) {
  return BluetoothPrinterService.fitReceiptPng(png, PaperSize.mm58.width);
}

class BluetoothPrinterService {
  BluetoothPrinterService._();

  static const _macKey = 'tmsx_bt_printer_mac';
  static const _nameKey = 'tmsx_bt_printer_name';
  static const _maxBtWrite = 12 * 1024;
  static const _previewWidth = 720;

  static Future<PairedPrinter?> savedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_macKey)?.trim() ?? '';
    if (mac.isEmpty) return null;
    return PairedPrinter(
      name: prefs.getString(_nameKey)?.trim() ?? mac,
      mac: mac,
    );
  }

  static Future<void> savePrinter(PairedPrinter printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macKey, printer.mac);
    await prefs.setString(_nameKey, printer.name);
  }

  static Future<void> clearPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_macKey);
    await prefs.remove(_nameKey);
  }

  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final requests = <Permission>[];
    if (Platform.isAndroid) {
      requests.addAll([
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ]);
    } else {
      requests.add(Permission.bluetooth);
    }
    for (final permission in requests) {
      final status = await permission.status;
      if (!status.isGranted) {
        await permission.request();
      }
    }

    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted) {
      throw Exception(
        'Izin Bluetooth belum diberikan. Izinkan Nearby Devices untuk aplikasi ini.',
      );
    }
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw Exception('Bluetooth HP masih mati. Nyalakan Bluetooth lalu coba lagi.');
    }
  }

  static Future<List<PairedPrinter>> pairedPrinters() async {
    await ensurePermissions();
    final rows = await PrintBluetoothThermal.pairedBluetooths;
    return [
      for (final row in rows)
        PairedPrinter(
          name: row.name.trim().isEmpty ? row.macAdress : row.name.trim(),
          mac: row.macAdress,
        ),
    ];
  }

  static Future<void> connect(String mac) async {
    await ensurePermissions();
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected) {
      await PrintBluetoothThermal.disconnect;
    }
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!ok) {
      throw Exception(
        'Gagal menyambung ke printer. Pastikan printer sudah pairing di HP dan menyala.',
      );
    }
  }

  static Future<List<ReceiptPage>> prepareReceiptImages(List<int> pdfBytes) async {
    final pages = <ReceiptPage>[];
    await for (final page in Printing.raster(
      Uint8List.fromList(pdfBytes),
      dpi: 140.0,
    )) {
      final png = await page.toPng();
      final pair = await compute(_fitReceiptIsolate, png);
      if (pair != null && pair.length == 2) {
        pages.add(ReceiptPage(previewPng: pair[0], printPng: pair[1]));
      }
    }
    if (pages.isEmpty) {
      throw Exception('PDF dari ERPNext tidak bisa diubah menjadi preview struk.');
    }
    return pages;
  }

  static Future<void> printReceiptImages(List<ReceiptPage> pages) async {
    final printer = await savedPrinter();
    if (printer == null) {
      throw Exception('Printer Bluetooth belum dipilih.');
    }
    if (pages.isEmpty) {
      throw Exception('Preview struk kosong.');
    }
    await connect(printer.mac);

    final paper = PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);

    await _writeCommand(generator.reset());
    await _writeCommand(const [27, 51, 0]);
    await _writeCommand(const [27, 97, 0]);

    for (var i = 0; i < pages.length; i++) {
      if (i > 0) await _writeCommand(generator.feed(1));
      final strips = _escPosImageStrips(pages[i].printPng, paper.width);
      for (final strip in strips) {
        await _writeCommand(strip, settleMs: 220);
      }
    }

    await _writeCommand(const [27, 50]);
    await _writeCommand(generator.feed(4));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _writeCommand(generator.cut());
  }

  static Future<void> printPdfBytes(List<int> pdfBytes) async {
    final pages = await prepareReceiptImages(pdfBytes);
    await printReceiptImages(pages);
  }

  static List<Uint8List>? fitReceiptPng(Uint8List png, int targetWidth) {
    final decoded = img.decodeImage(png);
    if (decoded == null) return null;
    var work = decoded.numChannels == 4 ? _flattenWhite(decoded) : decoded;
    if (work.width > _previewWidth) {
      work = img.copyResize(
        work,
        width: _previewWidth,
        interpolation: img.Interpolation.linear,
      );
    }
    work = img.grayscale(work);
    work = _trimWhitespace(work);

    final preview = work.width > _previewWidth
        ? img.copyResize(
            work,
            width: _previewWidth,
            interpolation: img.Interpolation.linear,
          )
        : work;

    final width = targetWidth - (targetWidth % 8);
    var printImage = work;
    if (printImage.width != width) {
      printImage = img.copyResize(
        printImage,
        width: width,
        interpolation: img.Interpolation.linear,
      );
    }
    printImage = img.luminanceThreshold(printImage, threshold: 0.72);

    return [
      Uint8List.fromList(img.encodeJpg(preview, quality: 88)),
      Uint8List.fromList(img.encodePng(printImage)),
    ];
  }

  static img.Image _flattenWhite(img.Image source) {
    final out = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 3,
    );
    img.fill(out, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(out, source);
    return out;
  }

  static img.Image _trimWhitespace(img.Image source) {
    const threshold = 210;
    const step = 2;
    var minX = source.width;
    var minY = source.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < source.height; y += step) {
      for (var x = 0; x < source.width; x += step) {
        final pixel = source.getPixel(x, y);
        if ((pixel.r + pixel.g + pixel.b) / 3 >= threshold) continue;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < minX || maxY < minY) return source;
    const pad = 10;
    minX = math.max(0, minX - pad);
    minY = math.max(0, minY - pad);
    maxX = math.min(source.width - 1, maxX + pad);
    maxY = math.min(source.height - 1, maxY + pad);
    return img.copyCrop(
      source,
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  static List<List<int>> _escPosImageStrips(Uint8List png, int targetWidth) {
    final decoded = img.decodeImage(png);
    if (decoded == null) return const [];
    var work = decoded;
    final width = targetWidth - (targetWidth % 8);
    if (work.width != width) {
      work = img.copyResize(
        work,
        width: width,
        interpolation: img.Interpolation.linear,
      );
    }

    final bytesPerRow = width ~/ 8;
    final maxRows = math.max(24, (_maxBtWrite - 8) ~/ bytesPerRow);
    final strip = math.min(240, maxRows - (maxRows % 8));
    final commands = <List<int>>[];
    for (var y = 0; y < work.height; y += strip) {
      final height = math.min(strip, work.height - y);
      final slice = img.copyCrop(
        work,
        x: 0,
        y: y,
        width: work.width,
        height: height,
      );
      commands.add(_gsv0Command(slice));
    }
    return commands;
  }

  static List<int> _gsv0Command(img.Image image) {
    final width = image.width;
    final height = image.height;
    final widthBytes = (width + 7) ~/ 8;
    final raster = Uint8List(widthBytes * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        if ((pixel.r + pixel.g + pixel.b) / 3 >= 128) continue;
        raster[y * widthBytes + (x >> 3)] |= 128 >> (x & 7);
      }
    }
    return <int>[
      0x1D,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
      ...raster,
    ];
  }

  static Future<void> _writeCommand(
    List<int> bytes, {
    int settleMs = 80,
  }) async {
    if (bytes.isEmpty) return;
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      throw Exception('Printer terputus saat mencetak. Coba pairing ulang.');
    }
    await Future<void>.delayed(Duration(milliseconds: settleMs));
  }
}
