class SpgAssignmentRow {
  final String salesPerson;
  final String employee;
  final String employeeName;
  final String customer;
  final String customerName;
  final DateTime? start;
  final DateTime? end;

  const SpgAssignmentRow({
    required this.salesPerson,
    required this.employee,
    required this.employeeName,
    required this.customer,
    required this.customerName,
    this.start,
    this.end,
  });

  bool overlaps(DateTime from, DateTime to) {
    final startDay = start == null
        ? null
        : DateTime(start!.year, start!.month, start!.day);
    final endDay = end == null
        ? null
        : DateTime(end!.year, end!.month, end!.day);
    if (startDay != null && startDay.isAfter(to)) return false;
    if (endDay != null && endDay.isBefore(from)) return false;
    return true;
  }
}

class SpgNamedOption {
  final String id;
  final String label;

  const SpgNamedOption(this.id, this.label);
}

class SpgAssignmentScope {
  final bool restricted;
  final bool lockEmployee;
  final String lockedEmployee;
  final String lockedEmployeeName;
  final List<SpgAssignmentRow> rows;
  final String error;

  const SpgAssignmentScope({
    required this.restricted,
    required this.lockEmployee,
    this.lockedEmployee = '',
    this.lockedEmployeeName = '',
    this.rows = const [],
    this.error = '',
  });

  const SpgAssignmentScope.unrestricted({this.rows = const []})
    : restricted = false,
      lockEmployee = false,
      lockedEmployee = '',
      lockedEmployeeName = '',
      error = '';

  List<SpgNamedOption> get employees => _unique(
    rows.map(
      (row) => SpgNamedOption(
        row.employee,
        row.employeeName.trim().isEmpty ? row.employee : row.employeeName,
      ),
    ),
  );

  List<SpgNamedOption> storesFor(String? employee) {
    final selected = employee?.trim() ?? '';
    return _unique(
      rows
          .where(
            (row) => selected.isEmpty || row.employee == selected,
          )
          .map(
            (row) => SpgNamedOption(
              row.customer,
              row.customerName.trim().isEmpty ? row.customer : row.customerName,
            ),
          ),
    );
  }

  static List<SpgNamedOption> _unique(Iterable<SpgNamedOption> source) {
    final map = <String, String>{};
    for (final option in source) {
      if (option.id.trim().isEmpty) continue;
      map.putIfAbsent(option.id, () => option.label);
    }
    final options = [
      for (final entry in map.entries) SpgNamedOption(entry.key, entry.value),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return options;
  }
}

class SpgCustomerOption {
  final String id;
  final String name;
  final String address;

  const SpgCustomerOption({
    required this.id,
    required this.name,
    this.address = '',
  });

  factory SpgCustomerOption.fromJson(Map<String, dynamic> json) {
    final id = json['name']?.toString() ?? '';
    return SpgCustomerOption(
      id: id,
      name: json['customer_name']?.toString() ?? id,
      address: json['primary_address']?.toString() ?? '',
    );
  }
}
