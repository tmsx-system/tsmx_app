import '../../visits/attendance_tab.dart';

class SalesVisitTab extends AttendanceTab {
  const SalesVisitTab({super.key, super.showCheckIn, super.showHistory})
    : super(spgMode: false);
}

class SalesVisitCheckInScreen extends AttendanceCheckInScreen {
  const SalesVisitCheckInScreen({super.key}) : super(spgMode: false);
}
