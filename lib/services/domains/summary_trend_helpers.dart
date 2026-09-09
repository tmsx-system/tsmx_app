import '../../models/erp_summary.dart';

class SummaryTrendHelpers {
  static const _monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static List<DocumentTrendPoint> emptyTrendPoints(int year, int month) {
    if (month == 0) {
      return [
        for (final label in _monthLabels) DocumentTrendPoint(label: label),
      ];
    }

    final lastDay = DateTime(year, month + 1, 0).day;
    final weeks = <int>{};
    for (var day = 1; day <= lastDay; day += 1) {
      weeks.add(isoWeekNumber(DateTime(year, month, day)));
    }
    final sortedWeeks = weeks.toList()..sort();
    return [
      for (final week in sortedWeeks) DocumentTrendPoint(label: 'Minggu $week'),
    ];
  }

  static void addTrendPoint(
    List<DocumentTrendPoint> points, {
    required int year,
    required int month,
    required dynamic dateRaw,
    required double amount,
  }) {
    final date = DateTime.tryParse(dateRaw?.toString() ?? '');
    if (date == null || date.year != year) return;

    final index = month == 0 ? date.month - 1 : weeklyTrendIndex(points, date);
    if (index < 0 || index >= points.length) return;
    points[index] = points[index].add(amount);
  }

  static int weeklyTrendIndex(List<DocumentTrendPoint> points, DateTime date) {
    final label = 'Minggu ${isoWeekNumber(date)}';
    final index = points.indexWhere(
      (point) => point.label.toLowerCase() == label.toLowerCase(),
    );
    if (index >= 0) return index;
    return ((date.day - 1) ~/ 7).clamp(0, points.length - 1);
  }

  static int isoWeekNumber(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final thursday = normalized.add(Duration(days: 4 - normalized.weekday));
    final firstThursdayBase = DateTime(thursday.year, 1, 4);
    final firstThursday = firstThursdayBase.add(
      Duration(days: 4 - firstThursdayBase.weekday),
    );
    return 1 + thursday.difference(firstThursday).inDays ~/ 7;
  }
}
