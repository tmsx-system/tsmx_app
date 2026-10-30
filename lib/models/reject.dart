class RejectSummary {
  final String id;
  final String postingDate;
  final String company;
  final String customer;
  final String stockEntry;
  final String workflowState;
  final String keterangan;

  const RejectSummary({
    required this.id,
    this.postingDate = '',
    this.company = '',
    this.customer = '',
    this.stockEntry = '',
    this.workflowState = '',
    this.keterangan = '',
  });

  factory RejectSummary.fromJson(Map<String, dynamic> json) {
    return RejectSummary(
      id: json['name']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      stockEntry: json['stock_entry']?.toString() ?? '',
      workflowState:
          json['workflow_state']?.toString() ??
          json['status']?.toString() ??
          '',
      keterangan: json['keterangan']?.toString() ?? '',
    );
  }

  String get statusLabel {
    final value = workflowState.trim();
    return value.isEmpty ? 'Draft' : value;
  }
}

class RejectItemDraft {
  final String itemCode;
  final String itemName;
  final String sourceWarehouse;
  final double qty;
  final String uom;

  const RejectItemDraft({
    required this.itemCode,
    this.itemName = '',
    required this.sourceWarehouse,
    required this.qty,
    this.uom = '',
  });

  Map<String, dynamic> toFrappeJson({
    String childDoctype = 'Reject Item',
    String warehouseField = 'source_warehouse',
  }) {
    return {
      'doctype': childDoctype,
      'item_code': itemCode.trim(),
      if (itemName.trim().isNotEmpty) 'item_name': itemName.trim(),
      warehouseField: sourceWarehouse.trim(),
      'qty': qty,
      if (uom.trim().isNotEmpty) 'uom': uom.trim(),
    };
  }
}

class RejectDraft {
  final String? namingSeries;
  final DateTime postingDate;
  final String company;
  final String customer;
  final String keterangan;
  final List<RejectItemDraft> items;

  const RejectDraft({
    this.namingSeries,
    required this.postingDate,
    required this.company,
    required this.customer,
    this.keterangan = '',
    required this.items,
  });

  Map<String, dynamic> toFrappeJson({
    String childTableField = 'reject_item',
    String childDoctype = 'Reject Item',
    String warehouseField = 'source_warehouse',
  }) {
    final date =
        '${postingDate.year.toString().padLeft(4, '0')}-'
        '${postingDate.month.toString().padLeft(2, '0')}-'
        '${postingDate.day.toString().padLeft(2, '0')}';
    return {
      'doctype': 'Reject',
      if ((namingSeries ?? '').trim().isNotEmpty)
        'naming_series': namingSeries!.trim(),
      'posting_date': date,
      'company': company.trim(),
      'customer': customer.trim(),
      if (keterangan.trim().isNotEmpty) 'keterangan': keterangan.trim(),
      childTableField: [
        for (final item in items)
          item.toFrappeJson(
            childDoctype: childDoctype,
            warehouseField: warehouseField,
          ),
      ],
    };
  }
}

class RejectMeta {
  final String childTableField;
  final String childDoctype;
  final String warehouseField;

  const RejectMeta({
    this.childTableField = 'reject_item',
    this.childDoctype = 'Reject Item',
    this.warehouseField = 'source_warehouse',
  });
}
