import '../utils/num_parse.dart';
import '../utils/frappe_status.dart';

class PosClosingPaymentRow {
  final String modeOfPayment;
  final double openingAmount;
  final double expectedAmount;
  final double closingAmount;

  const PosClosingPaymentRow({
    required this.modeOfPayment,
    this.openingAmount = 0,
    this.expectedAmount = 0,
    this.closingAmount = 0,
  });

  factory PosClosingPaymentRow.fromJson(Map<String, dynamic> json) {
    return PosClosingPaymentRow(
      modeOfPayment: json['mode_of_payment']?.toString() ?? '',
      openingAmount: NumParse.asDouble(json['opening_amount']),
      expectedAmount: NumParse.asDouble(json['expected_amount']),
      closingAmount: NumParse.asDouble(json['closing_amount']),
    );
  }
}

class PosClosingEntry {
  final String id;
  final String company;
  final String posProfile;
  final String user;
  final String posOpeningEntry;
  final String periodStartDate;
  final String periodEndDate;
  final String postingDate;
  final String statusText;
  final int docStatus;
  final double grandTotal;
  final List<PosClosingPaymentRow> paymentReconciliation;

  const PosClosingEntry({
    required this.id,
    this.company = '',
    this.posProfile = '',
    this.user = '',
    this.posOpeningEntry = '',
    this.periodStartDate = '',
    this.periodEndDate = '',
    this.postingDate = '',
    this.statusText = '',
    this.docStatus = 0,
    this.grandTotal = 0,
    this.paymentReconciliation = const [],
  });

  factory PosClosingEntry.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    final rawPayments = json['payment_reconciliation'];
    final payments = rawPayments is List
        ? rawPayments
              .whereType<Map>()
              .map(
                (row) => PosClosingPaymentRow.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList()
        : const <PosClosingPaymentRow>[];

    return PosClosingEntry(
      id: json['name']?.toString() ?? 'UNKNOWN',
      company: json['company']?.toString() ?? '',
      posProfile: json['pos_profile']?.toString() ?? '',
      user: json['user']?.toString() ?? '',
      posOpeningEntry: json['pos_opening_entry']?.toString() ?? '',
      periodStartDate: json['period_start_date']?.toString() ?? '',
      periodEndDate: json['period_end_date']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      grandTotal: NumParse.asDouble(json['grand_total']),
      paymentReconciliation: payments,
    );
  }
}
