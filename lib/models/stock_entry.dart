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

class StockEntryItemLine {
  final String itemCode;
  final String itemName;
  final double qty;
  final String uom;
  final String sourceWarehouse;
  final String targetWarehouse;
  final String costCenter;
  final double basicRate;
  final double amount;

  const StockEntryItemLine({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.uom,
    this.sourceWarehouse = '',
    this.targetWarehouse = '',
    this.costCenter = '',
    this.basicRate = 0,
    this.amount = 0,
  });

  factory StockEntryItemLine.fromJson(Map<String, dynamic> json) {
    final qty = NumParse.asDouble(json['qty'] ?? json['transfer_qty']);
    final rate = NumParse.asDouble(json['basic_rate'] ?? json['valuation_rate']);
    return StockEntryItemLine(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      qty: qty,
      uom: json['uom']?.toString() ?? json['stock_uom']?.toString() ?? '',
      sourceWarehouse: json['s_warehouse']?.toString() ?? '',
      targetWarehouse: json['t_warehouse']?.toString() ?? '',
      costCenter: json['cost_center']?.toString() ?? '',
      basicRate: rate,
      amount: NumParse.asDouble(json['amount']) > 0
          ? NumParse.asDouble(json['amount'])
          : qty * rate,
    );
  }
}

class StockEntryDetail {
  final String id;
  final String namingSeries;
  final String stockEntryType;
  final String purpose;
  final String company;
  final String statusText;
  final int docStatus;
  final String postingDate;
  final String postingTime;
  final String fromWarehouse;
  final String toWarehouse;
  final String remarks;
  final double totalQty;
  final List<StockEntryItemLine> items;

  const StockEntryDetail({
    required this.id,
    this.namingSeries = '',
    required this.stockEntryType,
    this.purpose = '',
    this.company = '',
    required this.statusText,
    this.docStatus = 0,
    required this.postingDate,
    this.postingTime = '',
    this.fromWarehouse = '',
    this.toWarehouse = '',
    this.remarks = '',
    this.totalQty = 0,
    this.items = const [],
  });

  factory StockEntryDetail.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    final rawItems = json['items'];
    return StockEntryDetail(
      id: json['name']?.toString() ?? '',
      namingSeries: json['naming_series']?.toString() ?? '',
      stockEntryType: json['stock_entry_type']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      postingDate: json['posting_date']?.toString() ?? '',
      postingTime: json['posting_time']?.toString() ?? '',
      fromWarehouse: json['from_warehouse']?.toString() ?? '',
      toWarehouse: json['to_warehouse']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
      totalQty: NumParse.asDouble(json['total_qty']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (row) => StockEntryItemLine.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class StockReconciliationSummary {
  final String id;
  final String company;
  final String date;
  final String postingTime;
  final String statusText;
  final int docStatus;
  final double differenceAmount;
  final String expenseAccount;
  final String costCenter;

  const StockReconciliationSummary({
    required this.id,
    required this.company,
    required this.date,
    this.postingTime = '',
    required this.statusText,
    required this.docStatus,
    required this.differenceAmount,
    this.expenseAccount = '',
    this.costCenter = '',
  });

  factory StockReconciliationSummary.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    return StockReconciliationSummary(
      id: json['name']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      date: json['posting_date']?.toString() ?? '',
      postingTime: json['posting_time']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      differenceAmount: NumParse.asDouble(json['difference_amount']),
      expenseAccount: json['expense_account']?.toString() ?? '',
      costCenter: json['cost_center']?.toString() ?? '',
    );
  }
}

class StockReconciliationItemLine {
  final String itemCode;
  final String itemName;
  final String warehouse;
  final double currentQty;
  final double qty;
  final String uom;
  final double valuationRate;
  final double amount;
  final double currentAmount;
  final String batchNo;

  const StockReconciliationItemLine({
    required this.itemCode,
    required this.itemName,
    required this.warehouse,
    required this.currentQty,
    required this.qty,
    required this.uom,
    this.valuationRate = 0,
    this.amount = 0,
    this.currentAmount = 0,
    this.batchNo = '',
  });

  double get qtyDifference => qty - currentQty;

  factory StockReconciliationItemLine.fromJson(Map<String, dynamic> json) {
    return StockReconciliationItemLine(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      currentQty: NumParse.asDouble(json['current_qty']),
      qty: NumParse.asDouble(json['qty']),
      uom: json['stock_uom']?.toString() ?? json['uom']?.toString() ?? '',
      valuationRate: NumParse.asDouble(json['valuation_rate']),
      amount: NumParse.asDouble(json['amount']),
      currentAmount: NumParse.asDouble(json['current_amount']),
      batchNo: json['batch_no']?.toString() ?? '',
    );
  }
}

class StockReconciliationDetail {
  final String id;
  final String purpose;
  final String company;
  final String postingDate;
  final String postingTime;
  final String warehouse;
  final String expenseAccount;
  final String costCenter;
  final String remarks;
  final String statusText;
  final int docStatus;
  final double differenceAmount;
  final List<StockReconciliationItemLine> items;

  const StockReconciliationDetail({
    required this.id,
    required this.purpose,
    required this.company,
    required this.postingDate,
    required this.postingTime,
    required this.warehouse,
    required this.expenseAccount,
    required this.costCenter,
    required this.remarks,
    required this.statusText,
    required this.docStatus,
    required this.differenceAmount,
    required this.items,
  });

  factory StockReconciliationDetail.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    final rawItems = json['items'];
    return StockReconciliationDetail(
      id: json['name']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      postingTime: json['posting_time']?.toString() ?? '',
      warehouse: json['set_warehouse']?.toString() ?? '',
      expenseAccount: json['expense_account']?.toString() ?? '',
      costCenter: json['cost_center']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      differenceAmount: NumParse.asDouble(json['difference_amount']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (row) => StockReconciliationItemLine.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList()
          : const [],
    );
  }
}
