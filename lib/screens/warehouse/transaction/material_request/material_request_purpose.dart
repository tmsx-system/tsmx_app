import 'package:flutter/material.dart';

import '../../shared/warehouse_widgets.dart';

class MaterialRequestPurpose {
  final String name;
  final bool needsSource;
  final bool needsTarget;
  final bool needsCustomer;
  final bool showPrice;
  final IconData icon;
  final Color color;
  final String summary;

  const MaterialRequestPurpose({
    required this.name,
    required this.needsSource,
    required this.needsTarget,
    this.needsCustomer = false,
    this.showPrice = true,
    required this.icon,
    required this.color,
    required this.summary,
  });

  static const all = <MaterialRequestPurpose>[
    MaterialRequestPurpose(
      name: 'Purchase',
      needsSource: false,
      needsTarget: true,
      icon: Icons.shopping_bag_outlined,
      color: warehouseBlue,
      summary: 'Permintaan pembelian barang menuju gudang tujuan.',
    ),
    MaterialRequestPurpose(
      name: 'Material Transfer',
      needsSource: true,
      needsTarget: true,
      showPrice: false,
      icon: Icons.swap_horiz_rounded,
      color: warehouseOrange,
      summary: 'Pindahkan stok dari gudang asal ke gudang tujuan.',
    ),
    MaterialRequestPurpose(
      name: 'Material Issue',
      needsSource: false,
      needsTarget: true,
      icon: Icons.outbox_rounded,
      color: warehouseCyan,
      summary: 'Keluarkan barang pada gudang tujuan. Scan barcode tidak dipakai.',
    ),
    MaterialRequestPurpose(
      name: 'Manufacture',
      needsSource: false,
      needsTarget: true,
      icon: Icons.precision_manufacturing_outlined,
      color: warehouseBlue,
      summary: 'Minta bahan untuk proses produksi.',
    ),
    MaterialRequestPurpose(
      name: 'Customer Provided',
      needsSource: false,
      needsTarget: true,
      needsCustomer: true,
      icon: Icons.person_pin_outlined,
      color: warehouseGreen,
      summary: 'Catat barang yang disediakan customer.',
    ),
  ];
}
