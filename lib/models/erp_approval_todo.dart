import '../utils/num_parse.dart';

class ErpApprovalTodo {
  final String doctype;
  final String name;
  final String party;
  final String partyName;
  final String workflowState;
  final String status;
  final String owner;
  final String date;
  final double amount;
  final double secondaryAmount;
  final int docStatus;
  final List<String> actions;

  const ErpApprovalTodo({
    required this.doctype,
    required this.name,
    required this.party,
    required this.partyName,
    required this.workflowState,
    required this.status,
    required this.owner,
    required this.date,
    required this.amount,
    this.secondaryAmount = 0,
    required this.docStatus,
    required this.actions,
  });

  String get moduleLabel => switch (doctype) {
    'Sales Order' => 'Sales Order',
    'Purchase Order' => 'Purchase Order',
    'Purchase Invoice' => 'Purchase Invoice',
    'Material Request' => 'Material Request',
    'Journal Entry' => 'Journal Entry',
    _ => doctype,
  };

  String get partyLabel {
    if (partyName.trim().isNotEmpty) return partyName.trim();
    if (party.trim().isNotEmpty) return party.trim();
    return moduleLabel;
  }

  factory ErpApprovalTodo.fromJson(
    String doctype,
    Map<String, dynamic> json, {
    required List<String> actions,
  }) {
    final party = switch (doctype) {
      'Sales Order' => json['customer']?.toString() ?? '',
      'Purchase Order' ||
      'Purchase Invoice' => json['supplier']?.toString() ?? '',
      'Material Request' => json['material_request_type']?.toString() ?? '',
      'Journal Entry' => json['company']?.toString() ?? '',
      _ => '',
    };
    final partyName = switch (doctype) {
      'Sales Order' =>
        json['customer_name']?.toString() ?? json['customer']?.toString() ?? '',
      'Purchase Order' || 'Purchase Invoice' =>
        json['supplier_name']?.toString() ?? json['supplier']?.toString() ?? '',
      'Material Request' =>
        json['company']?.toString() ??
            json['material_request_type']?.toString() ??
            '',
      'Journal Entry' =>
        json['title']?.toString() ?? json['company']?.toString() ?? '',
      _ => '',
    };
    final date = switch (doctype) {
      'Purchase Invoice' => json['posting_date']?.toString() ?? '',
      _ =>
        json['transaction_date']?.toString() ??
            json['posting_date']?.toString() ??
            json['schedule_date']?.toString() ??
            '',
    };
    final amount = switch (doctype) {
      'Material Request' => NumParse.asDouble(json['total_qty']),
      'Journal Entry' => NumParse.asDouble(
        json['total_debit'] ?? json['total_credit'],
      ),
      _ => NumParse.asDouble(json['grand_total'] ?? json['rounded_total']),
    };

    return ErpApprovalTodo(
      doctype: doctype,
      name: json['name']?.toString() ?? '',
      party: party,
      partyName: partyName,
      workflowState: json['workflow_state']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      owner: json['owner']?.toString() ?? '',
      date: date,
      amount: amount,
      secondaryAmount: NumParse.asDouble(json['outstanding_amount']),
      docStatus: NumParse.asInt(json['docstatus']),
      actions: actions,
    );
  }

  ErpApprovalTodo withActions(List<String> actions) {
    return ErpApprovalTodo(
      doctype: doctype,
      name: name,
      party: party,
      partyName: partyName,
      workflowState: workflowState,
      status: status,
      owner: owner,
      date: date,
      amount: amount,
      secondaryAmount: secondaryAmount,
      docStatus: docStatus,
      actions: actions,
    );
  }
}
