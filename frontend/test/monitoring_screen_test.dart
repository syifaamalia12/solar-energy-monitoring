import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/models/dashboard_data.dart';
import 'package:solar_energy_monitoring/models/sensor_reading.dart';
import 'package:solar_energy_monitoring/screens/monitoring_screen.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';
import 'package:solar_energy_monitoring/services/monitoring_service.dart';

class DashboardTestService implements DashboardService {
  DashboardTestService(this.handler);

  final Future<DashboardData?> Function() handler;
  int calls = 0;

  @override
  Future<DashboardData?> fetchDashboard() {
    calls++;
    return handler();
  }
}

class MonitoringTestService implements MonitoringService {
  MonitoringTestService(this.handler);

  final Future<List<SensorReading>> Function() handler;
  int calls = 0;
  final List<int> requestedLimits = [];

  @override
  Future<List<SensorReading>> fetchReadings({int limit = 100}) {
    calls++;
    requestedLimits.add(limit);
    return handler();
  }
}

DashboardData sampleDashboard() {
  return DashboardData(
    deviceId: 'solar-001',
    voltageV: 5,
    currentA: 0.5,
    powerW: 2.5,
    totalEnergyWh: 2,
    summaryDate: '2026-11-02',
    readingTimestamp: DateTime.utc(2026, 11, 2, 10),
    isTestData: false,
    readingCount: 8,
  );
}

SensorReading sampleReading() {
  return SensorReading(
    readingId: 'test-reading-1',
    deviceId: 'solar-001',
    timestamp: DateTime.utc(2026, 11, 2, 10),
    voltageV: 5,
    currentA: 0.5,
    powerW: 2.5,
    energyWh: 0.5,
    intervalSeconds: 60,
  );
}

Future<void> openMonitoring(
  WidgetTester tester, {
  required DashboardService dashboard,
  required MonitoringService monitoring,
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
          padding: const EdgeInsets.all(12),
          child: MonitoringScreen(
            dashboardService: dashboard,
            service: monitoring,
          ),
        ),
      ),
    ),
  );
}

Future<void> tapLabel(WidgetTester tester, String label) async {
  final finder = find.text(label);

  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Monitoring menampilkan loading selama menunggu data', (
    tester,
  ) async {
    final pending = Completer<List<SensorReading>>();
    final dashboard = DashboardTestService(() async => null);
    final monitoring = MonitoringTestService(() => pending.future);

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);

    expect(find.text('Memuat monitoring...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);

    pending.complete([]);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Data monitoring belum tersedia.'), findsOneWidget);
  });

  testWidgets('Monitoring membedakan energi harian dan energi interval', (
    tester,
  ) async {
    final dashboard = DashboardTestService(() async => sampleDashboard());
    final monitoring = MonitoringTestService(() async => [sampleReading()]);

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);
    await tester.pumpAndSettle();

    expect(dashboard.calls, 1);
    expect(monitoring.calls, 1);
    expect(monitoring.requestedLimits, [100]);

    // Total harian berasal dari DashboardData.
    expect(find.text('2.0000 Wh'), findsOneWidget);

    // Energi interval berasal dari SensorReading di tabel.
    final intervalTable = tester.widget<DataTable>(find.byType(DataTable));

    expect(
      intervalTable.rows.single.cells[4].child,
      isA<Text>().having(
        (text) => text.data,
        'nilai energi interval',
        '0.5000',
      ),
    );

    expect(find.text('Wh/interval'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);

    final graphTab = find.widgetWithText(ChoiceChip, 'Grafik');

    await tester.ensureVisible(graphTab);
    await tester.tap(graphTab);
    await tester.pumpAndSettle();

    expect(find.text('Energi per interval pengukuran'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);

    final chart = tester.widget<LineChart>(find.byType(LineChart));

    expect(chart.data.lineBarsData, hasLength(1));

    final points = chart.data.lineBarsData.single.spots;

    expect(points, hasLength(1));

    // Satu pembacaan ditampilkan di tengah grafik.
    // Nilai Y dinormalisasi terhadap energi terbesar.
    expect(points.single.x, 0.5);
    expect(points.single.y, 1);

    // Mengganti tampilan tidak membuat request baru.
    expect(dashboard.calls, 1);
    expect(monitoring.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Monitoring kosong tidak membuat angka atau tabel buatan', (
    tester,
  ) async {
    final dashboard = DashboardTestService(() async => null);
    final monitoring = MonitoringTestService(() async => []);

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);
    await tester.pumpAndSettle();

    expect(find.text('Data monitoring belum tersedia.'), findsOneWidget);
    expect(find.text('Muat ulang'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('0.0000 Wh'), findsNothing);
  });

  testWidgets('Coba lagi memulihkan Monitoring setelah error cepat', (
    tester,
  ) async {
    var attempts = 0;

    final dashboard = DashboardTestService(() async => sampleDashboard());

    final monitoring = MonitoringTestService(() {
      attempts++;

      if (attempts == 1) {
        throw const MonitoringApiException(
          'Tidak dapat terhubung ke server. Periksa koneksi internet.',
        );
      }

      return Future.value([sampleReading()]);
    });

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);
    await tester.pumpAndSettle();

    expect(
      find.text('Tidak dapat terhubung ke server. Periksa koneksi internet.'),
      findsOneWidget,
    );
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);

    await tapLabel(tester, 'Coba lagi');

    expect(monitoring.calls, 2);
    expect(dashboard.calls, 2);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Coba lagi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Refresh gagal menyembunyikan data lama dan dapat dipulihkan', (
    tester,
  ) async {
    var attempts = 0;

    final dashboard = DashboardTestService(() async => sampleDashboard());

    final monitoring = MonitoringTestService(() {
      attempts++;

      if (attempts == 2) {
        throw const MonitoringApiException(
          'Waktu permintaan habis. Silakan coba lagi.',
        );
      }

      return Future.value([sampleReading()]);
    });

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);

    await tapLabel(tester, 'Muat ulang');

    expect(
      find.text('Waktu permintaan habis. Silakan coba lagi.'),
      findsOneWidget,
    );
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('2.0000 Wh'), findsNothing);
    expect(tester.takeException(), isNull);

    await tapLabel(tester, 'Coba lagi');

    expect(monitoring.calls, 3);
    expect(dashboard.calls, 3);
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Monitoring mengambil ulang data tepat setelah 60 detik', (
    tester,
  ) async {
    final dashboard = DashboardTestService(() async => null);
    final monitoring = MonitoringTestService(() async => []);

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);
    await tester.pumpAndSettle();

    expect(monitoring.calls, 1);
    expect(dashboard.calls, 1);

    await tester.pump(const Duration(seconds: 59));

    expect(monitoring.calls, 1);
    expect(dashboard.calls, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(monitoring.calls, 2);
    expect(dashboard.calls, 2);
  });

  testWidgets('Request Monitoring tidak bertumpuk saat masih loading', (
    tester,
  ) async {
    final pending = Completer<List<SensorReading>>();
    final dashboard = DashboardTestService(() async => null);
    var attempts = 0;

    final monitoring = MonitoringTestService(() {
      attempts++;

      return attempts == 1 ? pending.future : Future.value(<SensorReading>[]);
    });

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);

    await tester.pump(const Duration(seconds: 60));

    expect(monitoring.calls, 1);
    expect(dashboard.calls, 1);

    pending.complete([]);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    expect(monitoring.calls, 2);
    expect(dashboard.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Timer Monitoring berhenti di background dan aktif saat resumed',
    (tester) async {
      final dashboard = DashboardTestService(() async => null);
      final monitoring = MonitoringTestService(() async => []);

      await openMonitoring(
        tester,
        dashboard: dashboard,
        monitoring: monitoring,
      );
      await tester.pumpAndSettle();

      expect(monitoring.calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      await tester.pump(const Duration(minutes: 2));

      expect(monitoring.calls, 1);
      expect(dashboard.calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(monitoring.calls, 2);
      expect(dashboard.calls, 2);

      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();

      expect(monitoring.calls, 3);
      expect(dashboard.calls, 3);
    },
  );

  testWidgets('Timer berhenti setelah halaman Monitoring dilepas', (
    tester,
  ) async {
    final dashboard = DashboardTestService(() async => null);
    final monitoring = MonitoringTestService(() async => []);

    await openMonitoring(tester, dashboard: dashboard, monitoring: monitoring);
    await tester.pumpAndSettle();

    expect(monitoring.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));

    expect(monitoring.calls, 1);
    expect(dashboard.calls, 1);
    expect(tester.takeException(), isNull);
  });
}
