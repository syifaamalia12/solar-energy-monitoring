import '../models/dashboard_data.dart';

abstract class DashboardService {
  Future<DashboardData?> fetchDashboard();
}

class MockDashboardService implements DashboardService {
  MockDashboardService({required this.deviceId});

  final String deviceId;

  @override
  Future<DashboardData?> fetchDashboard() async {
    return DashboardData(
      deviceId: deviceId,
      voltageV: 5.00,
      currentA: 0.20,
      powerW: 1.00,
      totalEnergyWh: 0.75,
      summaryDate: '2026-11-01',
      readingTimestamp: DateTime.parse('2026-11-01T12:00:00+07:00'),
      isTestData: true,
    );
  }
}
