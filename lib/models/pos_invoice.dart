import '../utils/num_parse.dart';
import '../utils/frappe_status.dart';

export '../utils/frappe_status.dart'
    show InvoiceStatusKey, parseInvoiceStatus, normalizeStatusText;

class PosInvoiceItem {
  final String itemCode;
  final String itemName;
  final double qty;
  final double rate;
  final double amount;
  final String warehouse;
  final String uom;

  const PosInvoiceItem({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.rate,
    required this.amount,
    this.warehouse = '',
    this.uom = '',
  });

  factory PosInvoiceItem.fromJson(Map<String, dynamic> json) {
    final itemCode = json['item_code']?.toString() ?? '';
    return PosInvoiceItem(
      itemCode: itemCode,
      itemName:
          json['item_name']?.toString() ??
          (itemCode.isNotEmpty ? itemCode : 'Unknown Item'),
      qty: NumParse.asDouble(json['qty'] ?? json['stock_qty']),
      rate: NumParse.asDouble(json['rate'] ?? json['net_rate']),
      amount: NumParse.asDouble(json['amount'] ?? json['net_amount']),
      warehouse: json['warehouse']?.toString() ?? '',
      uom: json['uom']?.toString() ?? json['stock_uom']?.toString() ?? '',
    );
  }
}

class PosInvoicePayment {
  final String modeOfPayment;
  final double amount;

  const PosInvoicePayment({required this.modeOfPayment, this.amount = 0});

  factory PosInvoicePayment.fromJson(Map<String, dynamic> json) {
    return PosInvoicePayment(
      modeOfPayment: json['mode_of_payment']?.toString() ?? '',
      amount: NumParse.asDouble(json['amount']),
    );
  }
}

class PosInvoice {
  final String id;
  final String customer;
  final String customerName;
  final String company;
  final String posProfile;
  final String postingDate;
  final double value;
  final double outstandingAmount;
  final InvoiceStatusKey statusKey;
  final String statusText;
  final int docStatus;
  final int isPos;
  final List<PosInvoiceItem> items;
  final List<PosInvoicePayment> payments;

  const PosInvoice({
    required this.id,
    this.customer = '',
    this.customerName = '',
    this.company = '',
    this.posProfile = '',
    this.postingDate = '',
    this.value = 0,
    this.outstandingAmount = 0,
    this.statusKey = InvoiceStatusKey.draft,
    this.statusText = '',
    this.docStatus = 0,
    this.isPos = 1,
    this.items = const [],
    this.payments = const [],
  });

  String get party =>
      customerName.trim().isNotEmpty ? customerName : customer;

  factory PosInvoice.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    final statusText = normalizeStatusText(
      json['status']?.toString(),
      docstatus: docstatus,
    );
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (row) =>
                    PosInvoiceItem.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList()
        : const <PosInvoiceItem>[];
    final rawPayments = json['payments'];
    final payments = rawPayments is List
        ? rawPayments
              .whereType<Map>()
              .map(
                (row) => PosInvoicePayment.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList()
        : const <PosInvoicePayment>[];

    return PosInvoice(
      id: json['name']?.toString() ?? 'UNKNOWN',
      customer: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      posProfile: json['pos_profile']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      value: NumParse.asDouble(
        json['grand_total'] ?? json['rounded_total'] ?? json['net_total'],
      ),
      outstandingAmount: NumParse.asDouble(json['outstanding_amount']),
      statusKey: parseInvoiceStatus(statusText, docstatus: docstatus),
      statusText: statusText,
      docStatus: docstatus,
      isPos: NumParse.asInt(json['is_pos'], fallback: 1),
      items: items,
      payments: payments,
    );
  }
}
