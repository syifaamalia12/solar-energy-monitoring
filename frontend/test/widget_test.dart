import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/main.dart';
import 'package:solar_energy_monitoring/models/daily_energy.dart';
import 'package:solar_energy_monitoring/models/dashboard_data.dart';
import 'package:solar_energy_monitoring/models/energy_prediction.dart';
import 'package:solar_energy_monitoring/models/sensor_reading.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';
import 'package:solar_energy_monitoring/services/history_service.dart';
import 'package:solar_energy_monitoring/services/monitoring_service.dart';
import 'package:solar_energy_monitoring/services/prediction_service.dart';

class EmptyDashboardService implements DashboardService {
  @override
  Future<DashboardData?> fetchDashboard() async => null;
}

class EmptyHistoryService implements HistoryService {
  @override
  Future<List<DailyEnergy>> fetchHistory({required int days}) async => [];
}

class EmptyPredictionService implements PredictionService {
  @override
  Future<EnergyPrediction?> fetchLatestPrediction() async => null;
}

class EmptyMonitoringService implements MonitoringService {
  @override
  Future<List<SensorReading>> fetchReadings({int limit = 100}) async => [];
}

Future<void> openApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  await tester.pumpWidget(
    MyApp(
      dashboardService: EmptyDashboardService(),
      historyService: EmptyHistoryService(),
      predictionService: EmptyPredictionService(),
      monitoringService: EmptyMonitoringService(),
    ),
  );
  await tester.pumpAndSettle();
}

String? pageTitle(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(const ValueKey('page-title'))).data;
}

Future<void> openTab(WidgetTester tester, String label) async {
  final destination = find.widgetWithText(NavigationDestination, label);

  await tester.tap(destination);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Aplikasi membuka Beranda tanpa login', (tester) async {
    await openApp(tester);

    expect(pageTitle(tester), 'Dashboard Monitoring');
    expect(find.text('Login'), findsNothing);
    expect(find.text('Perangkat: solar-001'), findsNothing);
  });

  testWidgets('Navigasi memiliki lima menu sesuai mockup', (tester) async {
    await openApp(tester);

    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));

    expect(navigation.destinations, hasLength(5));

    for (final label in [
      'Beranda',
      'Monitoring',
      'Prediksi',
      'Riwayat',
      'Pengaturan',
    ]) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
  });

  testWidgets('Seluruh menu dapat dibuka', (tester) async {
    await openApp(tester);

    await openTab(tester, 'Monitoring');
    expect(pageTitle(tester), 'Monitoring');
    expect(find.text('Data monitoring belum tersedia.'), findsOneWidget);

    await openTab(tester, 'Prediksi');
    expect(pageTitle(tester), 'Prediksi Energi');

    await openTab(tester, 'Riwayat');
    expect(pageTitle(tester), 'Riwayat Energi');

    await openTab(tester, 'Pengaturan');
    expect(pageTitle(tester), 'Pengaturan');
    expect(find.text('Informasi Perangkat'), findsOneWidget);

    await openTab(tester, 'Beranda');
    expect(pageTitle(tester), 'Dashboard Monitoring');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tombol kembali dari menu lain menuju Beranda', (tester) async {
    await openApp(tester);

    for (final label in ['Monitoring', 'Prediksi', 'Riwayat', 'Pengaturan']) {
      await openTab(tester, label);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(pageTitle(tester), 'Dashboard Monitoring');
    }

    expect(tester.takeException(), isNull);
  });
}
