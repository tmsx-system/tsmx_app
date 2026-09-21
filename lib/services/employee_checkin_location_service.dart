import 'package:geolocator/geolocator.dart';

class EmployeeCheckinLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime capturedAt;

  const EmployeeCheckinLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
  });

  factory EmployeeCheckinLocation.fromPosition(Position position) {
    return EmployeeCheckinLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      capturedAt: position.timestamp,
    );
  }
}

class EmployeeCheckinLocationService {
  Future<EmployeeCheckinLocation> currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw Exception('GPS belum aktif.');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Izin lokasi ditolak.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Izin lokasi ditolak permanen. Aktifkan melalui pengaturan perangkat.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 25),
      ),
    );
    if (position.isMocked) {
      throw Exception(
        'Lokasi palsu terdeteksi (Fake GPS). Matikan mock location, lalu coba lagi.',
      );
    }
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        (position.latitude == 0 && position.longitude == 0)) {
      throw Exception('Koordinat GPS tidak valid. Aktifkan lokasi akurat.');
    }
    if (position.accuracy > 120) {
      throw Exception(
        'Akurasi GPS terlalu rendah (${position.accuracy.round()} m). Pastikan GPS HP aktif, bukan Fake GPS.',
      );
    }
    return EmployeeCheckinLocation.fromPosition(position);
  }

  double distanceMeters({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    return Geolocator.distanceBetween(
      fromLatitude,
      fromLongitude,
      toLatitude,
      toLongitude,
    );
  }
}
