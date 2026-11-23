class StockOpnameSummary {
  final String id;
  final String postingDate;
  final String postingTime;
  final String company;
  final String warehouse;
  final String itemGroup;
  final String statusPenyelesaian;
  final int docstatus;

  const StockOpnameSummary({
    required this.id,
    this.postingDate = '',
    this.postingTime = '',
    this.company = '',
    this.warehouse = '',
    this.itemGroup = '',
    this.statusPenyelesaian = '',
    this.docstatus = 0,
  });

  factory StockOpnameSummary.fromJson(Map<String, dynamic> json) {
    return StockOpnameSummary(
      id: json['name']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      postingTime: json['posting_time']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      itemGroup: json['item_group']?.toString() ?? '',
      statusPenyelesaian: json['status_penyelesaian']?.toString() ?? '',
      docstatus: int.tryParse(json['docstatus']?.toString() ?? '') ?? 0,
    );
  }

  String get docStatusLabel {
    if (docstatus == 1) return 'Submitted';
    if (docstatus == 2) return 'Cancelled';
    return 'Draft';
  }
}

class StockOpnameLine {
  final String itemCode;
  final String itemName;
  final String itemGroup;
  final double stockAwal;
  final double stockFisik;
  final String uom;
  final bool sudahDicek;
  final String keterangan;

  const StockOpnameLine({
    required this.itemCode,
    this.itemName = '',
    this.itemGroup = '',
    this.stockAwal = 0,
    this.stockFisik = 0,
    this.uom = '',
    this.sudahDicek = false,
    this.keterangan = '',
  });

  double get selisih => stockFisik - stockAwal;

  factory StockOpnameLine.fromJson(Map<String, dynamic> json) {
    return StockOpnameLine(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      itemGroup: json['item_group']?.toString() ?? '',
      stockAwal: _asDouble(json['stock_awal']),
      stockFisik: _asDouble(json['stock_fisik']),
      uom: json['uom']?.toString() ?? '',
      sudahDicek: json['sudah_dicek'] == 1 || json['sudah_dicek'] == true,
      keterangan: json['keterangan']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toFrappeJson({String? parent}) {
    final name = (parent ?? '').trim();
    return {
      'doctype': 'Stock Opname Detail',
      'parenttype': 'Stock Opname',
      'parentfield': 'stock_opname_detail',
      if (name.isNotEmpty) 'parent': name,
      'item_code': itemCode.trim(),
      if (itemName.trim().isNotEmpty) 'item_name': itemName.trim(),
      if (itemGroup.trim().isNotEmpty) 'item_group': itemGroup.trim(),
      'stock_awal': stockAwal,
      'stock_fisik': stockFisik,
      if (uom.trim().isNotEmpty) 'uom': uom.trim(),
      'sudah_dicek': sudahDicek ? 1 : 0,
      if (keterangan.trim().isNotEmpty) 'keterangan': keterangan.trim(),
    };
  }
}

class StockOpnameDraft {
  final String? namingSeries;
  final String company;
  final DateTime postingDate;
  final String postingTime;
  final String warehouse;
  final String itemGroup;
  final List<StockOpnameLine> lines;

  const StockOpnameDraft({
    this.namingSeries,
    required this.company,
    required this.postingDate,
    required this.postingTime,
    required this.warehouse,
    required this.itemGroup,
    required this.lines,
  });

  Map<String, dynamic> toFrappeJson({String? parentName}) {
    final parent = (parentName ?? '').trim();
    final date =
        '${postingDate.year.toString().padLeft(4, '0')}-'
        '${postingDate.month.toString().padLeft(2, '0')}-'
        '${postingDate.day.toString().padLeft(2, '0')}';
    return {
      'doctype': 'Stock Opname',
      if (parent.isNotEmpty) 'name': parent,
      if (parent.isEmpty && (namingSeries ?? '').trim().isNotEmpty)
        'naming_series': namingSeries!.trim(),
      'company': company.trim(),
      'posting_date': date,
      'posting_time': postingTime.trim(),
      'warehouse': warehouse.trim(),
      'item_group': itemGroup.trim(),
      if (parent.isEmpty) 'status_penyelesaian': 'Open',
      'stock_opname_detail': [
        for (final line in lines) line.toFrappeJson(parent: parent),
      ],
    };
  }
}

class StockOpnameItemChoice {
  final String code;
  final String name;
  final String itemGroup;
  final String uom;

  const StockOpnameItemChoice({
    required this.code,
    required this.name,
    this.itemGroup = '',
    this.uom = '',
  });
}

class StockOpnameSettlement {
  final String id;
  final int docstatus;
  final String postingDate;

  const StockOpnameSettlement({
    required this.id,
    this.docstatus = 0,
    this.postingDate = '',
  });
}

double _asDouble(Object? value) {
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

String formatStockQty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.replaceFirst(RegExp(r'\.$'), '');
}

String? stockOpnameSubmitError(List<StockOpnameLine> lines) {
  if (lines.isEmpty) return 'Tidak bisa Submit. Pilih minimal satu SKU.';
  final errors = <String>[];
  for (final line in lines) {
    final name = line.itemName.trim().isEmpty ? line.itemCode : line.itemName;
    final unit = line.uom.trim().isEmpty ? 'Box' : line.uom.trim();
    if (line.stockFisik <= 0) {
      errors.add('$name: Stock Fisik harus lebih dari 0 $unit.');
    }
    if (!line.sudahDicek) {
      errors.add('$name: Belum dicentang Sudah Dicek.');
    }
  }
  if (errors.isEmpty) return null;
  return errors.join('\n');
}
