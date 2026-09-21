class EmployeeAttendanceSnapshot {
  final String employee;
  final String employeeName;
  final String lastLogType;
  final String lastInTime;
  final String lastOutTime;

  const EmployeeAttendanceSnapshot({
    this.employee = '',
    this.employeeName = '',
    this.lastLogType = '',
    this.lastInTime = '',
    this.lastOutTime = '',
  });

  bool get hasEmployee => employee.trim().isNotEmpty;
  bool get needsCheckIn => lastLogType != 'IN';
  bool get needsCheckOut => lastLogType == 'IN';

  String get lastInDisplay => _displayTime(lastInTime);
  String get lastOutDisplay => _displayTime(lastOutTime);

  static String _displayTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parts = value.split(' ');
    if (parts.length < 2) return value;
    final clock = parts.last;
    return clock.length >= 5 ? clock.substring(0, 5) : clock;
  }
}
