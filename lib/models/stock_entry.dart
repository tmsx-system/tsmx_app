import '../utils/frappe_status.dart';
import '../utils/num_parse.dart';

class StockEntryType {
  final String name;
  final String purpose;

  const StockEntryType({required this.name, required this.purpose});

  factory StockEntryType.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final purpose = json['purpose']?.toString().trim() ?? '';
    return StockEntryType(
      name: name,
      purpose: purpose.isEmpty ? name : purpose,
    );
  }
}

class StockEntry {
  final String id;
  final String stockEntryType;
  final String company;
  final String statusText;
  final int docStatus;
  final String date;
  final int itemsCount;
  final String fromWarehouse;
  final String toWarehouse;

  StockEntry({
    required this.id,
    required this.stockEntryType,
    this.company = '',
    required this.statusText,
    this.docStatus = 0,
    required this.date,
    required this.itemsCount,
    this.fromWarehouse = '',
    this.toWarehouse = '',
  });

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    return StockEntry(
      id: json['name']?.toString() ?? 'UNKNOWN',
      stockEntryType: json['stock_entry_type']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      date: json['posting_date']?.toString() ?? '',
      itemsCount: NumParse.asInt(json['total_qty']),
      fromWarehouse: json['from_warehouse']?.toString() ?? '',
      toWarehouse: json['to_warehouse']?.toString() ?? '',
    );
  }
}

class StockReconciliationSummary {
  final String id;
  final String company;
  final String date;
  final String statusText;
  final int docStatus;
  final double differenceAmount;

  const StockReconciliationSummary({
    required this.id,
    required this.company,
    required this.date,
    required this.statusText,
    required this.docStatus,
    required this.differenceAmount,
  });

  factory StockReconciliationSummary.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    return StockReconciliationSummary(
      id: json['name']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      date: json['posting_date']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      differenceAmount: NumParse.asDouble(json['difference_amount']),
    );
  }
}
