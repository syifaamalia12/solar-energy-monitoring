import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solar_energy_monitoring/models/dashboard_data.dart';
import 'package:solar_energy_monitoring/screens/dashboard_screen.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';

class ConditionsService implements DashboardService {
  ConditionsService(this.data);

  final DashboardData? data;
  int calls = 0;

  @override
  Future<DashboardData?> fetchDashboard() async {
    calls++;
    return data;
  }
}

DashboardData zeroReading(DateTime timestamp) {
  return DashboardData(
    deviceId: 'solar-001',
    voltageV: 0,
    currentA: 0,
    powerW: 0,
    totalEnergyWh: 0,
    summaryDate: '2026-11-01',
    readingTimestamp: timestamp,
    isTestData: false,
    readingCount: 1,
  );
}

Future<void> openDashboard(
  WidgetTester tester, {
  required DashboardService service,
  required DateTime now,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardScreen(service: service, now: () => now),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Data lebih dari 3 menit diberi keterangan', (tester) async {
    final now = DateTime.utc(2026, 11, 1, 5);
    final service = ConditionsService(
      zeroReading(now.subtract(const Duration(minutes: 3, seconds: 1))),
    );

    await openDashboard(tester, service: service, now: now);

    expect(find.text('Belum ada data terbaru'), findsOneWidget);

    // Pembacaan lama tetap ditampilkan, tidak diganti data kosong.
    expect(find.text('0.00 V'), findsOneWidget);
  });

  testWidgets('Data tepat 3 menit belum diberi peringatan', (tester) async {
    final now = DateTime.utc(2026, 11, 1, 5);
    final service = ConditionsService(
      zeroReading(now.subtract(const Duration(minutes: 3))),
    );

    await openDashboard(tester, service: service, now: now);

    expect(find.text('Belum ada data terbaru'), findsNothing);
  });

  testWidgets('Nilai nol tetap tampil ketika ada pembacaan', (tester) async {
    final now = DateTime.utc(2026, 11, 1, 5);
    final service = ConditionsService(zeroReading(now));

    await openDashboard(tester, service: service, now: now);

    expect(find.text('0.00 V'), findsOneWidget);
    expect(find.text('0.0000 A'), findsOneWidget);
    expect(find.text('0.0000 W'), findsOneWidget);
    expect(find.text('0.0000 Wh'), findsOneWidget);
    expect(find.text('-- Wh'), findsNothing);
    expect(find.text('Belum ada data energi hari ini.'), findsNothing);
  });

  testWidgets('Timer berhenti di latar belakang dan aktif kembali', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 1, 5);
    final service = ConditionsService(null);

    await openDashboard(tester, service: service, now: now);
    expect(service.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    await tester.pump(const Duration(minutes: 2));
    expect(service.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Aplikasi kembali aktif: langsung mengambil ulang.
    expect(service.calls, 2);

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    // Timer berjalan lagi.
    expect(service.calls, 3);
  });
}
