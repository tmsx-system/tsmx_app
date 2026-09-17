import '../utils/num_parse.dart';
import '../utils/frappe_status.dart';

class PosOpeningBalanceDetail {
  final String modeOfPayment;
  final double openingAmount;

  const PosOpeningBalanceDetail({
    required this.modeOfPayment,
    this.openingAmount = 0,
  });

  factory PosOpeningBalanceDetail.fromJson(Map<String, dynamic> json) {
    return PosOpeningBalanceDetail(
      modeOfPayment: json['mode_of_payment']?.toString() ?? '',
      openingAmount: NumParse.asDouble(json['opening_amount']),
    );
  }
}

class PosOpeningEntry {
  final String id;
  final String company;
  final String posProfile;
  final String user;
  final String periodStartDate;
  final String postingDate;
  final String statusText;
  final int docStatus;
  final List<PosOpeningBalanceDetail> balanceDetails;

  const PosOpeningEntry({
    required this.id,
    this.company = '',
    this.posProfile = '',
    this.user = '',
    this.periodStartDate = '',
    this.postingDate = '',
    this.statusText = '',
    this.docStatus = 0,
    this.balanceDetails = const [],
  });

  double get totalOpeningAmount =>
      balanceDetails.fold(0, (sum, row) => sum + row.openingAmount);

  factory PosOpeningEntry.fromJson(Map<String, dynamic> json) {
    final docstatus = NumParse.asInt(json['docstatus']);
    final rawBalance = json['balance_details'];
    final balanceDetails = rawBalance is List
        ? rawBalance
              .whereType<Map>()
              .map(
                (row) => PosOpeningBalanceDetail.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList()
        : const <PosOpeningBalanceDetail>[];

    return PosOpeningEntry(
      id: json['name']?.toString() ?? 'UNKNOWN',
      company: json['company']?.toString() ?? '',
      posProfile: json['pos_profile']?.toString() ?? '',
      user: json['user']?.toString() ?? '',
      periodStartDate: json['period_start_date']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      statusText: normalizeStatusText(
        json['status']?.toString(),
        docstatus: docstatus,
      ),
      docStatus: docstatus,
      balanceDetails: balanceDetails,
    );
  }
}
