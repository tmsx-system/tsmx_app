class TukarGulingSummary {
  final String id;
  final String postingDate;
  final String company;
  final String customer;
  final String stockEntry;
  final String workflowState;
  final String keterangan;
  final int docstatus;

  const TukarGulingSummary({
    required this.id,
    this.postingDate = '',
    this.company = '',
    this.customer = '',
    this.stockEntry = '',
    this.workflowState = '',
    this.keterangan = '',
    this.docstatus = 0,
  });

  factory TukarGulingSummary.fromJson(Map<String, dynamic> json) {
    return TukarGulingSummary(
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
      docstatus: int.tryParse(json['docstatus']?.toString() ?? '') ?? 0,
    );
  }

  String get statusLabel {
    final value = workflowState.trim();
    return value.isEmpty ? 'Draft' : value;
  }
}

class TukarGulingClaimDraft {
  final DateTime claimDate;
  final String itemCode;
  final String itemName;
  final double qtyKg;
  final String keterangan;
  final String sourceName;

  const TukarGulingClaimDraft({
    required this.claimDate,
    required this.itemCode,
    this.itemName = '',
    required this.qtyKg,
    this.keterangan = '',
    this.sourceName = '',
  });

  Map<String, dynamic> toFrappeJson(TukarGulingMeta meta) {
    final date =
        '${claimDate.year.toString().padLeft(4, '0')}-'
        '${claimDate.month.toString().padLeft(2, '0')}-'
        '${claimDate.day.toString().padLeft(2, '0')}';
    return {
      'doctype': meta.claimDoctype,
      meta.claimDateField: date,
      meta.claimItemField: itemCode.trim(),
      if (itemName.trim().isNotEmpty) 'item_name': itemName.trim(),
      meta.claimQtyField: qtyKg,
      if (keterangan.trim().isNotEmpty) meta.claimNoteField: keterangan.trim(),
      if (sourceName.trim().isNotEmpty && meta.claimSourceField.isNotEmpty)
        meta.claimSourceField: sourceName.trim(),
      if (sourceName.trim().isNotEmpty && meta.claimAllocatedField.isNotEmpty)
        meta.claimAllocatedField: qtyKg,
    };
  }
}

class TukarGulingRemainder {
  final String sourceFinal;
  final String itemCode;
  final String itemName;
  final double qtyKg;
  final String postingDate;

  const TukarGulingRemainder({
    required this.sourceFinal,
    required this.itemCode,
    this.itemName = '',
    required this.qtyKg,
    this.postingDate = '',
  });
}

class TukarGulingBalance {
  final String itemCode;
  final String itemName;
  final double qtyKg;

  const TukarGulingBalance({
    required this.itemCode,
    this.itemName = '',
    required this.qtyKg,
  });
}

class TukarGulingDailyClaim {
  final String sourceName;
  final DateTime claimDate;
  final String itemCode;
  final String itemName;
  final double qtyKg;
  final String keterangan;

  const TukarGulingDailyClaim({
    required this.sourceName,
    required this.claimDate,
    required this.itemCode,
    this.itemName = '',
    required this.qtyKg,
    this.keterangan = '',
  });
}

class TukarGulingItemDraft {
  final String itemCode;
  final String itemName;
  final String sourceWarehouse;
  final double qty;
  final String uom;

  const TukarGulingItemDraft({
    required this.itemCode,
    this.itemName = '',
    required this.sourceWarehouse,
    required this.qty,
    this.uom = '',
  });

  Map<String, dynamic> toFrappeJson({
    String childDoctype = 'Tukar Guling Item',
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

class TukarGulingDraft {
  final String? namingSeries;
  final DateTime postingDate;
  final String company;
  final String customer;
  final String customerName;
  final String jenisInput;
  final String metodeFinal;
  final String keterangan;
  final DateTime? deliveryDate;
  final String deliveryNote;
  final double totalKg;
  final int totalBox;
  final double sisaKg;
  final List<TukarGulingClaimDraft> claims;
  final List<TukarGulingItemDraft> items;
  final List<TukarGulingRemainder> usedRemainders;
  final List<TukarGulingBalance> balances;

  const TukarGulingDraft({
    this.namingSeries,
    required this.postingDate,
    required this.company,
    required this.customer,
    this.customerName = '',
    this.jenisInput = 'Harian',
    this.metodeFinal = '',
    this.keterangan = '',
    this.deliveryDate,
    this.deliveryNote = '',
    this.totalKg = 0,
    this.totalBox = 0,
    this.sisaKg = 0,
    this.claims = const [],
    this.items = const [],
    this.usedRemainders = const [],
    this.balances = const [],
  });

  bool get isFinal => jenisInput.trim().toLowerCase() == 'final';

  Map<String, dynamic> toFrappeJson({
    TukarGulingMeta meta = const TukarGulingMeta(),
  }) {
    final date =
        '${postingDate.year.toString().padLeft(4, '0')}-'
        '${postingDate.month.toString().padLeft(2, '0')}-'
        '${postingDate.day.toString().padLeft(2, '0')}';
    return {
      'doctype': 'Tukar Guling',
      if ((namingSeries ?? '').trim().isNotEmpty)
        'naming_series': namingSeries!.trim(),
      meta.jenisField: isFinal ? 'Final' : 'Harian',
      if (isFinal && metodeFinal.trim().isNotEmpty)
        meta.metodeField: metodeFinal.trim(),
      'posting_date': date,
      'company': company.trim(),
      'customer': customer.trim(),
      if (customerName.trim().isNotEmpty)
        meta.customerNameField: customerName.trim(),
      if (!isFinal && keterangan.trim().isNotEmpty)
        'keterangan': keterangan.trim(),
      if (deliveryDate != null)
        'tanggal_pengiriman':
            '${deliveryDate!.year.toString().padLeft(4, '0')}-'
            '${deliveryDate!.month.toString().padLeft(2, '0')}-'
            '${deliveryDate!.day.toString().padLeft(2, '0')}',
      if (deliveryNote.trim().isNotEmpty)
        'no_delivery_note': deliveryNote.trim(),
      if (totalKg > 0) 'custom_total_kg': totalKg,
      if (isFinal && totalBox > 0) 'custom_total_box': totalBox,
      if (isFinal) 'custom_sisa_kg': sisaKg,
      if (isFinal &&
          usedRemainders.isNotEmpty &&
          meta.sourceDoctype.isNotEmpty)
        meta.sourceTableField: [
          for (final row in usedRemainders)
            {
              'doctype': meta.sourceDoctype,
              'source_final': row.sourceFinal,
              'item_code': row.itemCode,
              if (row.itemName.trim().isNotEmpty) 'item_name': row.itemName,
              'qty_kg': row.qtyKg,
            },
        ],
      if (isFinal && balances.isNotEmpty && meta.balanceDoctype.isNotEmpty)
        meta.balanceTableField: [
          for (final row in balances)
            {
              'doctype': meta.balanceDoctype,
              'item_code': row.itemCode,
              if (row.itemName.trim().isNotEmpty) 'item_name': row.itemName,
              'sisa_kg': row.qtyKg,
            },
        ],
      if (claims.isNotEmpty && metodeFinal.trim() != 'Input Langsung')
        meta.claimTableField: [
          for (final claim in claims) claim.toFrappeJson(meta),
        ],
      if (isFinal)
        meta.childTableField: [
          for (final item in items)
            item.toFrappeJson(
              childDoctype: meta.childDoctype,
              warehouseField: meta.warehouseField,
            ),
        ],
    };
  }
}

class TukarGulingMeta {
  final String childTableField;
  final String childDoctype;
  final String warehouseField;
  final String jenisField;
  final String metodeField;
  final String customerNameField;
  final String claimTableField;
  final String claimDoctype;
  final String claimDateField;
  final String claimItemField;
  final String claimQtyField;
  final String claimNoteField;
  final String claimSourceField;
  final String claimAllocatedField;
  final String sourceTableField;
  final String sourceDoctype;
  final String balanceTableField;
  final String balanceDoctype;

  const TukarGulingMeta({
    this.childTableField = 'tukar_guling_item',
    this.childDoctype = 'Tukar Guling Item',
    this.warehouseField = 'source_warehouse',
    this.jenisField = 'custom_jenis_input',
    this.metodeField = 'custom_metode_final',
    this.customerNameField = 'customer_name',
    this.claimTableField = 'custom_claim_details',
    this.claimDoctype = 'Tukar Guling Harian',
    this.claimDateField = 'posting_date',
    this.claimItemField = 'item',
    this.claimQtyField = 'qty_kg',
    this.claimNoteField = 'keterangan',
    this.claimSourceField = 'notg',
    this.claimAllocatedField = 'allocated_kg',
    this.sourceTableField = 'custom_sisa_sources',
    this.sourceDoctype = '',
    this.balanceTableField = 'saldo_sisa_per_sku',
    this.balanceDoctype = '',
  });

  TukarGulingMeta copyWith({
    String? childTableField,
    String? childDoctype,
    String? warehouseField,
  }) {
    return TukarGulingMeta(
      childTableField: childTableField ?? this.childTableField,
      childDoctype: childDoctype ?? this.childDoctype,
      warehouseField: warehouseField ?? this.warehouseField,
      jenisField: jenisField,
      metodeField: metodeField,
      customerNameField: customerNameField,
      claimTableField: claimTableField,
      claimDoctype: claimDoctype,
      claimDateField: claimDateField,
      claimItemField: claimItemField,
      claimQtyField: claimQtyField,
      claimNoteField: claimNoteField,
      claimSourceField: claimSourceField,
      claimAllocatedField: claimAllocatedField,
      sourceTableField: sourceTableField,
      sourceDoctype: sourceDoctype,
      balanceTableField: balanceTableField,
      balanceDoctype: balanceDoctype,
    );
  }
}
