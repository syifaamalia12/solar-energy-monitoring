import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';

void main() {
  test('Layanan simulasi mengembalikan data pengujian', () async {
    final service = MockDashboardService(deviceId: 'solar-001');

    final data = await service.fetchDashboard();

    expect(data, isNotNull);

    final result = data!;

    expect(result.deviceId, 'solar-001');
    expect(result.voltageV, 5.00);
    expect(result.currentA, 0.20);
    expect(result.powerW, 1.00);
    expect(result.totalEnergyWh, 0.75);
    expect(result.summaryDate, '2026-11-01');
    expect(result.readingTimestamp.toUtc(), DateTime.utc(2026, 11, 1, 5));
    expect(result.isTestData, isTrue);
  });

  test('Layanan simulasi mengikuti ID perangkat yang diberikan', () async {
    final service = MockDashboardService(deviceId: 'perangkat-uji');

    final data = await service.fetchDashboard();

    expect(data!.deviceId, 'perangkat-uji');
  });
}
