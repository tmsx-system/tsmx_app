import '../utils/num_parse.dart';

class SalesCustomerOption {
  final String id;
  final String name;
  final String address;
  final List<Map<String, dynamic>> salesTeam;

  const SalesCustomerOption({
    required this.id,
    required this.name,
    this.address = '',
    this.salesTeam = const [],
  });

  factory SalesCustomerOption.fromJson(Map<String, dynamic> json) {
    final id = json['name']?.toString() ?? '';
    return SalesCustomerOption(
      id: id,
      name: json['customer_name']?.toString() ?? id,
      address: json['primary_address']?.toString() ?? '',
      salesTeam: const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': id,
    'customer_name': name,
    'primary_address': address,
    'sales_team': salesTeam,
  };

  SalesCustomerOption copyWithSalesTeam(List<Map<String, dynamic>> rows) {
    return SalesCustomerOption(
      id: id,
      name: name,
      address: address,
      salesTeam: rows,
    );
  }
}

class CustomerItemPrice {
  final String itemCode;
  final String itemName;
  final String itemGroup;
  final String priceList;
  final String currency;
  final double rate;
  final String uom;
  final String validFrom;

  const CustomerItemPrice({
    required this.itemCode,
    required this.itemName,
    this.itemGroup = '',
    required this.priceList,
    this.currency = '',
    required this.rate,
    this.uom = '',
    this.validFrom = '',
  });

  factory CustomerItemPrice.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic> itemMeta = const {},
  }) {
    final itemCode = json['item_code']?.toString() ?? '';
    return CustomerItemPrice(
      itemCode: itemCode,
      itemName:
          itemMeta['item_name']?.toString() ??
          json['item_name']?.toString() ??
          itemCode,
      itemGroup: itemMeta['item_group']?.toString() ?? '',
      priceList: json['price_list']?.toString() ?? '',
      currency: json['currency']?.toString() ?? '',
      rate: NumParse.asDouble(json['price_list_rate']),
      uom: json['uom']?.toString() ?? itemMeta['stock_uom']?.toString() ?? '',
      validFrom: json['valid_from']?.toString() ?? '',
    );
  }
}

class CustomerVisitLocation {
  final String addressId;
  final String displayAddress;
  final double latitude;
  final double longitude;
  final double geofenceRadius;

  const CustomerVisitLocation({
    required this.addressId,
    required this.displayAddress,
    required this.latitude,
    required this.longitude,
    this.geofenceRadius = 50,
  });

  bool get isConfigured => latitude != 0 || longitude != 0;
}

class CollectionRanking {
  final String salesPerson;
  final double amount;
  final int rank;

  const CollectionRanking({
    required this.salesPerson,
    required this.amount,
    required this.rank,
  });

  factory CollectionRanking.fromJson(Map<String, dynamic> json) {
    return CollectionRanking(
      salesPerson:
          json['owner']?.toString() ??
          json['sales_person']?.toString() ??
          json['name']?.toString() ??
          'Unknown',
      amount: NumParse.asDouble(
        json['amount'] ?? json['collected_amount'] ?? json['total'],
      ),
      rank: NumParse.asInt(json['rank']),
    );
  }
}

class SalesPersonCustomerRanking {
  final String salesPerson;
  final String customer;
  final String customerName;
  final double amount;
  final int orderCount;
  final int rank;

  const SalesPersonCustomerRanking({
    required this.salesPerson,
    required this.customer,
    required this.customerName,
    required this.amount,
    required this.orderCount,
    required this.rank,
  });
}

class DailySalesReport {
  final List<DailySalesItemSummary> items;
  final List<DailySalesCustomerSummary> customers;
  final double totalQty;
  final double totalAmount;

  const DailySalesReport({
    this.items = const [],
    this.customers = const [],
    this.totalQty = 0,
    this.totalAmount = 0,
  });

  bool get isEmpty => items.isEmpty && customers.isEmpty;
}

class DailySalesItemSummary {
  final String itemLabel;
  final String itemGroup;
  final double qty;
  final double amount;

  const DailySalesItemSummary({
    required this.itemLabel,
    this.itemGroup = '',
    required this.qty,
    required this.amount,
  });
}

class DailySalesCustomerSummary {
  final String customer;
  final List<DailySalesItemSummary> items;
  final double totalAmount;

  const DailySalesCustomerSummary({
    required this.customer,
    required this.items,
    required this.totalAmount,
  });
}

class CollectionPayment {
  final String id;
  final String customer;
  final String customerName;
  final String postingDate;
  final double amount;
  final String referenceNo;
  final String remarks;
  final List<CollectionPaymentReference> references;

  const CollectionPayment({
    required this.id,
    required this.customer,
    required this.customerName,
    required this.postingDate,
    required this.amount,
    this.referenceNo = '',
    this.remarks = '',
    this.references = const [],
  });

  factory CollectionPayment.fromJson(Map<String, dynamic> json) {
    final customer = json['party']?.toString() ?? '';
    return CollectionPayment(
      id: json['name']?.toString() ?? '',
      customer: customer,
      customerName: json['party_name']?.toString() ?? customer,
      postingDate: json['posting_date']?.toString() ?? '',
      amount: NumParse.asDouble(json['received_amount'] ?? json['paid_amount']),
      referenceNo: json['reference_no']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
      references: _referencesFromJson(json['references']),
    );
  }

  CollectionPayment copyWithReferences(
    Iterable<CollectionPaymentReference> references,
  ) {
    return CollectionPayment(
      id: id,
      customer: customer,
      customerName: customerName,
      postingDate: postingDate,
      amount: amount,
      referenceNo: referenceNo,
      remarks: remarks,
      references: List<CollectionPaymentReference>.unmodifiable(references),
    );
  }

  static List<CollectionPaymentReference> _referencesFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (reference) => CollectionPaymentReference.fromJson(
            Map<String, dynamic>.from(reference),
          ),
        )
        .toList(growable: false);
  }

  Iterable<CollectionPaymentReference> get salesInvoiceReferences {
    return references.where(
      (reference) =>
          reference.doctype.trim().toLowerCase() == 'sales invoice' &&
          reference.documentName.trim().isNotEmpty,
    );
  }

  double get allocatedToSalesInvoices {
    return salesInvoiceReferences.fold<double>(
      0,
      (sum, reference) => sum + reference.allocatedAmount,
    );
  }

  double get unallocatedAmount {
    final unallocated = amount - allocatedToSalesInvoices;
    return unallocated > 0 ? unallocated : 0;
  }

  bool get isAllocatedToSalesInvoice => allocatedToSalesInvoices > 0;
}

class CollectionPaymentReference {
  final String doctype;
  final String documentName;
  final double allocatedAmount;

  const CollectionPaymentReference({
    required this.doctype,
    required this.documentName,
    required this.allocatedAmount,
  });

  factory CollectionPaymentReference.fromJson(Map<String, dynamic> json) {
    return CollectionPaymentReference(
      doctype: json['reference_doctype']?.toString() ?? '',
      documentName: json['reference_name']?.toString() ?? '',
      allocatedAmount: NumParse.asDouble(json['allocated_amount']),
    );
  }
}

class SalesInvoicePaymentAllocation {
  final String paymentEntry;
  final String invoice;
  final String postingDate;
  final String modeOfPayment;
  final String referenceNo;
  final double allocatedAmount;

  const SalesInvoicePaymentAllocation({
    required this.paymentEntry,
    required this.invoice,
    required this.allocatedAmount,
    this.postingDate = '',
    this.modeOfPayment = '',
    this.referenceNo = '',
  });

  factory SalesInvoicePaymentAllocation.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic> paymentEntry = const {},
  }) {
    return SalesInvoicePaymentAllocation(
      paymentEntry: json['parent']?.toString() ?? '',
      invoice: json['reference_name']?.toString() ?? '',
      allocatedAmount: NumParse.asDouble(json['allocated_amount']),
      postingDate: paymentEntry['posting_date']?.toString() ?? '',
      modeOfPayment: paymentEntry['mode_of_payment']?.toString() ?? '',
      referenceNo: paymentEntry['reference_no']?.toString() ?? '',
    );
  }
}

class SalesVisit {
  final String id;
  final String customer;
  final String customerName;
  final String salesPerson;
  final String employee;
  final String employeeCheckinIn;
  final String employeeCheckinOut;
  final String checkInTime;
  final String checkOutTime;
  final String status;
  final String notes;
  final String journeyStartTime;
  final String address;
  final double targetLatitude;
  final double targetLongitude;
  final double checkInLatitude;
  final double checkInLongitude;
  final double checkOutLatitude;
  final double checkOutLongitude;
  final double checkInDistance;
  final List<Map<String, dynamic>> competitors;
  final List<Map<String, dynamic>> potentialOrders;

  const SalesVisit({
    required this.id,
    required this.customer,
    this.customerName = '',
    required this.salesPerson,
    this.employee = '',
    this.employeeCheckinIn = '',
    this.employeeCheckinOut = '',
    required this.checkInTime,
    this.checkOutTime = '',
    this.status = 'Checked In',
    this.notes = '',
    this.journeyStartTime = '',
    this.address = '',
    this.targetLatitude = 0,
    this.targetLongitude = 0,
    this.checkInLatitude = 0,
    this.checkInLongitude = 0,
    this.checkOutLatitude = 0,
    this.checkOutLongitude = 0,
    this.checkInDistance = 0,
    this.competitors = const [],
    this.potentialOrders = const [],
  });

  factory SalesVisit.fromJson(Map<String, dynamic> json) {
    final customer = json['customer']?.toString() ?? '';
    final employeeCheckinIn = json['employee_checkin_in']?.toString() ?? '';
    final employeeCheckinOut = json['employee_checkin_out']?.toString() ?? '';
    final rawStatus = json['status']?.toString().trim() ?? '';
    final inferredStatus = employeeCheckinIn.isEmpty
        ? 'Draft'
        : employeeCheckinOut.isEmpty
        ? 'Checked In'
        : 'Checked Out';
    return SalesVisit(
      id: json['name']?.toString() ?? '',
      customer: customer,
      customerName: json['customer_name']?.toString() ?? customer,
      salesPerson: json['sales_person']?.toString() ?? '',
      employee: json['employee']?.toString() ?? '',
      employeeCheckinIn: employeeCheckinIn,
      employeeCheckinOut: employeeCheckinOut,
      checkInTime:
          json['check_in_time']?.toString() ??
          json['employee_checkin_in_time']?.toString() ??
          '',
      checkOutTime:
          json['check_out_time']?.toString() ??
          json['employee_checkin_out_time']?.toString() ??
          '',
      status: rawStatus.isEmpty ? inferredStatus : rawStatus,
      notes: json['notes']?.toString() ?? '',
      journeyStartTime: json['journey_start_time']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      targetLatitude: NumParse.asDouble(json['target_latitude']),
      targetLongitude: NumParse.asDouble(json['target_longitude']),
      checkInLatitude: NumParse.asDouble(json['check_in_latitude']),
      checkInLongitude: NumParse.asDouble(json['check_in_longitude']),
      checkOutLatitude: NumParse.asDouble(json['check_out_latitude']),
      checkOutLongitude: NumParse.asDouble(json['check_out_longitude']),
      checkInDistance: NumParse.asDouble(json['check_in_distance']),
      competitors: _mapRows(json['competitors']),
      potentialOrders: _mapRows(json['potential_orders']),
    );
  }

  static List<Map<String, dynamic>> _mapRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  bool get isActive {
    if (employeeCheckinIn.isNotEmpty) return employeeCheckinOut.isEmpty;
    return status.trim().toLowerCase() == 'checked in';
  }

  SalesVisit copyWith({
    String? checkInTime,
    String? checkOutTime,
    double? checkInLatitude,
    double? checkInLongitude,
    double? checkOutLatitude,
    double? checkOutLongitude,
  }) {
    return SalesVisit(
      id: id,
      customer: customer,
      customerName: customerName,
      salesPerson: salesPerson,
      employee: employee,
      employeeCheckinIn: employeeCheckinIn,
      employeeCheckinOut: employeeCheckinOut,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      status: status,
      notes: notes,
      journeyStartTime: journeyStartTime,
      address: address,
      targetLatitude: targetLatitude,
      targetLongitude: targetLongitude,
      checkInLatitude: checkInLatitude ?? this.checkInLatitude,
      checkInLongitude: checkInLongitude ?? this.checkInLongitude,
      checkOutLatitude: checkOutLatitude ?? this.checkOutLatitude,
      checkOutLongitude: checkOutLongitude ?? this.checkOutLongitude,
      checkInDistance: checkInDistance,
      competitors: competitors,
      potentialOrders: potentialOrders,
    );
  }
}
