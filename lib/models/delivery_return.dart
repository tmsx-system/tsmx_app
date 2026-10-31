class DeliveryReturnSummary {
  final String id;
  final String postingDate;
  final String company;
  final String customer;
  final String workflowState;
  final String keterangan;

  const DeliveryReturnSummary({
    required this.id,
    this.postingDate = '',
    this.company = '',
    this.customer = '',
    this.workflowState = '',
    this.keterangan = '',
  });

  factory DeliveryReturnSummary.fromJson(Map<String, dynamic> json) {
    return DeliveryReturnSummary(
      id: json['name']?.toString() ?? '',
      postingDate: json['posting_date']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
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

class DeliveryReturnItemDraft {
  final String itemCode;
  final String itemName;
  final double qtyDn;
  final double qtyTolak;
  final String uom;

  const DeliveryReturnItemDraft({
    required this.itemCode,
    this.itemName = '',
    required this.qtyDn,
    required this.qtyTolak,
    this.uom = '',
  });

  Map<String, dynamic> toFrappeJson({
    String childDoctype = 'Delivery Return Detail',
    String qtyDnField = 'qty_dn',
    String qtyTolakField = 'qty_tolak',
  }) {
    return {
      'doctype': childDoctype,
      'item_code': itemCode.trim(),
      if (itemName.trim().isNotEmpty) 'item_name': itemName.trim(),
      qtyDnField: qtyDn,
      qtyTolakField: qtyTolak,
      if (uom.trim().isNotEmpty) 'uom': uom.trim(),
    };
  }
}

class DeliveryReturnDraft {
  final String? namingSeries;
  final DateTime postingDate;
  final String company;
  final String customer;
  final String customerName;
  final String deliveryNote;
  final String keterangan;
  final List<DeliveryReturnItemDraft> items;

  const DeliveryReturnDraft({
    this.namingSeries,
    required this.postingDate,
    required this.company,
    required this.customer,
    this.customerName = '',
    this.deliveryNote = '',
    this.keterangan = '',
    required this.items,
  });

  Map<String, dynamic> toFrappeJson({
    String childTableField = 'return_detail',
    String childDoctype = 'Delivery Return Detail',
    String qtyDnField = 'qty_dn',
    String qtyTolakField = 'qty_tolak',
    String customerNameField = 'customer_name',
    String deliveryNoteField = 'delivery_asal',
    bool setDraftWorkflow = false,
  }) {
    final date =
        '${postingDate.year.toString().padLeft(4, '0')}-'
        '${postingDate.month.toString().padLeft(2, '0')}-'
        '${postingDate.day.toString().padLeft(2, '0')}';
    return {
      'doctype': 'Delivery Return',
      if ((namingSeries ?? '').trim().isNotEmpty)
        'naming_series': namingSeries!.trim(),
      'posting_date': date,
      'company': company.trim(),
      'customer': customer.trim(),
      if (setDraftWorkflow) 'workflow_state': 'Draft',
      if (customerName.trim().isNotEmpty)
        customerNameField: customerName.trim(),
      if (deliveryNote.trim().isNotEmpty)
        deliveryNoteField: deliveryNote.trim(),
      if (keterangan.trim().isNotEmpty) 'keterangan': keterangan.trim(),
      childTableField: [
        for (final item in items)
          item.toFrappeJson(
            childDoctype: childDoctype,
            qtyDnField: qtyDnField,
            qtyTolakField: qtyTolakField,
          ),
      ],
    };
  }
}

class DeliveryReturnMeta {
  final String childTableField;
  final String childDoctype;
  final String qtyDnField;
  final String qtyTolakField;
  final String customerNameField;
  final String deliveryNoteField;

  const DeliveryReturnMeta({
    this.childTableField = 'return_detail',
    this.childDoctype = 'Delivery Return Detail',
    this.qtyDnField = 'qty_dn',
    this.qtyTolakField = 'qty_tolak',
    this.customerNameField = 'customer_name',
    this.deliveryNoteField = 'delivery_asal',
  });
}
