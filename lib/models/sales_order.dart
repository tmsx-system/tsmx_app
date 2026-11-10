import '../utils/frappe_status.dart';
import '../utils/num_parse.dart';

export '../utils/frappe_status.dart'
    show SalesOrderStatusKey, parseSalesOrderStatus;

class SalesOrderItem {
  final String itemCode;
  final String itemName;
  final int qty;
  final double rate;
  final double priceListRate;
  final double discountAmount;
  final String warehouse;
  final String costCenter;
  final String deliveryDate;

  SalesOrderItem({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.rate,
    this.priceListRate = 0,
    this.discountAmount = 0,
    this.warehouse = '',
    this.costCenter = '',
    this.deliveryDate = '',
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) {
    final itemCode = json['item_code']?.toString() ?? '';
    return SalesOrderItem(
      itemCode: itemCode,
      itemName:
          json['item_name']?.toString() ??
          (itemCode.isNotEmpty ? itemCode : null) ??
          'Unknown Item',
      qty: NumParse.asInt(json['qty'] ?? json['stock_qty']),
      rate: NumParse.asDouble(json['rate'] ?? json['net_rate']),
      priceListRate: NumParse.asDouble(json['price_list_rate']),
      discountAmount: NumParse.asDouble(json['discount_amount']),
      warehouse: json['warehouse']?.toString() ?? '',
      costCenter: json['cost_center']?.toString() ?? '',
      deliveryDate: json['delivery_date']?.toString() ?? '',
    );
  }
}

class SalesOrder {
  final String id;
  final String customerId;
  final String customer;
  final double value;
  final SalesOrderStatusKey statusKey;
  final String statusText;
  final String workflowState;
  final int docStatus;
  final double perDelivered;
  final double perBilled;
  final String date;
  final String deliveryDate;
  final String salesPerson;
  final String currency;
  final String sellingPriceList;
  final String priceListCurrency;
  final String costCenter;
  final String noted;
  final bool ignorePricingRule;
  final int itemsCount;
  final List<SalesOrderItem> items;

  SalesOrder({
    required this.id,
    required this.customerId,
    required this.customer,
    required this.value,
    required this.statusKey,
    required this.statusText,
    this.workflowState = '',
    this.docStatus = 0,
    this.perDelivered = 0,
    this.perBilled = 0,
    required this.date,
    this.deliveryDate = '',
    this.salesPerson = '',
    this.currency = '',
    this.sellingPriceList = '',
    this.priceListCurrency = '',
    this.costCenter = '',
    this.noted = '',
    this.ignorePricingRule = false,
    required this.itemsCount,
    this.items = const [],
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    final id = json['name']?.toString() ?? json['id']?.toString() ?? 'UNKNOWN';

    final customer =
        json['customer_name']?.toString() ??
        json['customer']?.toString() ??
        'Unknown Customer';
    final customerId = json['customer']?.toString() ?? customer;

    final value = NumParse.asDouble(
      json['grand_total'] ?? json['rounded_total'] ?? json['net_total'],
    );

    final date =
        json['transaction_date']?.toString() ??
        json['delivery_date']?.toString() ??
        json['creation']?.toString() ??
        '';

    final itemsCount = NumParse.asInt(json['total_qty'] ?? json['items_count']);

    final docstatus = NumParse.asInt(json['docstatus']);
    final statusText = normalizeStatusText(
      json['status']?.toString(),
      docstatus: docstatus,
    );
    final statusKey = parseSalesOrderStatus(statusText, docstatus: docstatus);
    final workflowState = json['workflow_state']?.toString().trim() ?? '';

    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .map((e) => SalesOrderItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <SalesOrderItem>[];

    var salesPerson = '';
    final rawSalesTeam = json['sales_team'];
    if (rawSalesTeam is List) {
      for (final rawRow in rawSalesTeam) {
        if (rawRow is! Map) continue;
        final row = Map<String, dynamic>.from(rawRow);
        final value = row['sales_person']?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          salesPerson = value;
          break;
        }
      }
    }

    return SalesOrder(
      id: id,
      customerId: customerId,
      customer: customer,
      value: value,
      statusKey: statusKey,
      statusText: statusText,
      workflowState: workflowState,
      docStatus: NumParse.asInt(json['docstatus']),
      perDelivered: NumParse.asDouble(json['per_delivered']),
      perBilled: NumParse.asDouble(json['per_billed']),
      date: date,
      deliveryDate: json['delivery_date']?.toString() ?? '',
      salesPerson: salesPerson,
      currency: json['currency']?.toString() ?? '',
      sellingPriceList: json['selling_price_list']?.toString() ?? '',
      priceListCurrency: json['price_list_currency']?.toString() ?? '',
      costCenter: json['cost_center']?.toString() ?? '',
      noted: json['noted']?.toString() ?? '',
      ignorePricingRule:
          json['ignore_pricing_rule'] == 1 ||
          json['ignore_pricing_rule'] == true,
      itemsCount: itemsCount,
      items: items,
    );
  }

  SalesOrder copyWith({
    String? id,
    String? customerId,
    String? customer,
    double? value,
    SalesOrderStatusKey? statusKey,
    String? statusText,
    String? workflowState,
    int? docStatus,
    double? perDelivered,
    double? perBilled,
    String? date,
    String? deliveryDate,
    String? salesPerson,
    String? currency,
    String? sellingPriceList,
    String? priceListCurrency,
    String? costCenter,
    String? noted,
    bool? ignorePricingRule,
    int? itemsCount,
    List<SalesOrderItem>? items,
  }) {
    return SalesOrder(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customer: customer ?? this.customer,
      value: value ?? this.value,
      statusKey: statusKey ?? this.statusKey,
      statusText: statusText ?? this.statusText,
      workflowState: workflowState ?? this.workflowState,
      docStatus: docStatus ?? this.docStatus,
      perDelivered: perDelivered ?? this.perDelivered,
      perBilled: perBilled ?? this.perBilled,
      date: date ?? this.date,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      salesPerson: salesPerson ?? this.salesPerson,
      currency: currency ?? this.currency,
      sellingPriceList: sellingPriceList ?? this.sellingPriceList,
      priceListCurrency: priceListCurrency ?? this.priceListCurrency,
      costCenter: costCenter ?? this.costCenter,
      noted: noted ?? this.noted,
      ignorePricingRule: ignorePricingRule ?? this.ignorePricingRule,
      itemsCount: itemsCount ?? this.itemsCount,
      items: items ?? this.items,
    );
  }

  String get effectiveStatusText {
    final workflow = workflowState.trim();
    if (workflow.isNotEmpty) return workflow;
    return statusText;
  }

  SalesOrderStatusKey get effectiveStatusKey =>
      parseSalesOrderStatus(effectiveStatusText, docstatus: docStatus);
}
