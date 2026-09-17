import '../utils/num_parse.dart';

class PosProfile {
  final String id;
  final String company;
  final String warehouse;
  final String customer;
  final String sellingPriceList;
  final String currency;
  final int disabled;
  final String modified;

  const PosProfile({
    required this.id,
    this.company = '',
    this.warehouse = '',
    this.customer = '',
    this.sellingPriceList = '',
    this.currency = '',
    this.disabled = 0,
    this.modified = '',
  });

  bool get isDisabled => disabled == 1;

  factory PosProfile.fromJson(Map<String, dynamic> json) {
    return PosProfile(
      id: json['name']?.toString() ?? 'UNKNOWN',
      company: json['company']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      sellingPriceList: json['selling_price_list']?.toString() ?? '',
      currency: json['currency']?.toString() ?? '',
      disabled: NumParse.asInt(json['disabled']),
      modified: json['modified']?.toString() ?? '',
    );
  }
}
