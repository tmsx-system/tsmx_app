class EmployeeCheckinLog {
  final String id;
  final String logType;
  final String time;
  final double latitude;
  final double longitude;

  const EmployeeCheckinLog({
    required this.id,
    required this.logType,
    required this.time,
    this.latitude = 0,
    this.longitude = 0,
  });

  factory EmployeeCheckinLog.fromJson(Map<String, dynamic> json) {
    return EmployeeCheckinLog(
      id: json['name']?.toString() ?? '',
      logType: json['log_type']?.toString().trim().toUpperCase() ?? '',
      time: json['time']?.toString() ?? '',
      latitude: double.tryParse(json['latitude']?.toString() ?? '') ?? 0,
      longitude: double.tryParse(json['longitude']?.toString() ?? '') ?? 0,
    );
  }

  String get timeDisplay {
    final value = time.trim();
    if (value.isEmpty) return '-';
    final parts = value.split(' ');
    if (parts.length < 2) return value;
    final date = parts.first;
    final clock = parts.last;
    final hhmm = clock.length >= 5 ? clock.substring(0, 5) : clock;
    return '$date $hhmm';
  }
}

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
