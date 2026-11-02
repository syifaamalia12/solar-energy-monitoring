import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solar_energy_monitoring/main.dart';
import 'package:solar_energy_monitoring/models/daily_energy.dart';
import 'package:solar_energy_monitoring/models/dashboard_data.dart';
import 'package:solar_energy_monitoring/models/energy_prediction.dart';
import 'package:solar_energy_monitoring/screens/dashboard_screen.dart';
import 'package:solar_energy_monitoring/screens/history_screen.dart';
import 'package:solar_energy_monitoring/services/api_dashboard_service.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';
import 'package:solar_energy_monitoring/services/history_service.dart';
import 'package:solar_energy_monitoring/services/prediction_service.dart';

class DashboardStub implements DashboardService {
  DashboardStub(this.handler);

  final Future<DashboardData?> Function() handler;
  int calls = 0;

  @override
  Future<DashboardData?> fetchDashboard() {
    calls++;
    return handler();
  }
}

class HistoryStub implements HistoryService {
  HistoryStub(this.handler);

  final Future<List<DailyEnergy>> Function(int days) handler;
  final List<int> calls = [];

  @override
  Future<List<DailyEnergy>> fetchHistory({required int days}) {
    calls.add(days);
    return handler(days);
  }
}

class PredictionStub implements PredictionService {
  int calls = 0;

  @override
  Future<EnergyPrediction?> fetchLatestPrediction() async {
    calls++;
    return null;
  }
}

const connectionMessage =
    'Tidak dapat terhubung ke server. Periksa koneksi internet.';

Widget screenApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Future<void> tapText(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('Dashboard pulih setelah refresh gagal dengan cepat', (
    tester,
  ) async {
    var attempts = 0;
    final sample = MockDashboardService(deviceId: 'solar-001');

    final service = DashboardStub(() {
      attempts++;

      if (attempts == 2) {
        throw const DashboardApiException(connectionMessage);
      }

      return sample.fetchDashboard();
    });

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    await tester.pumpWidget(screenApp(DashboardScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('5.00 V'), findsOneWidget);

    await tapText(tester, 'Muat ulang');

    expect(find.text(connectionMessage), findsOneWidget);
    expect(find.text('5.00 V'), findsNothing);
    expect(tester.takeException(), isNull);

    await tapText(tester, 'Coba lagi');

    expect(service.calls, 3);
    expect(find.text('5.00 V'), findsOneWidget);
    expect(find.text(connectionMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Riwayat pulih setelah refresh gagal dengan cepat', (
    tester,
  ) async {
    var attempts = 0;

    final service = HistoryStub((days) {
      attempts++;

      if (attempts == 2) {
        throw const HistoryApiException(connectionMessage);
      }

      return Future.value([
        DailyEnergy(date: '2026-11-02', totalEnergyWh: 2, readingCount: 8),
      ]);
    });

    await tester.pumpWidget(screenApp(HistoryScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('2.0000 Wh'), findsOneWidget);

    await tapText(tester, 'Muat ulang');

    expect(find.text(connectionMessage), findsOneWidget);
    expect(find.text('2.0000 Wh'), findsNothing);
    expect(find.byKey(const ValueKey('history-chart')), findsNothing);
    expect(tester.takeException(), isNull);

    await tapText(tester, 'Coba lagi');

    expect(service.calls, [7, 7, 7]);
    expect(find.text('2.0000 Wh'), findsOneWidget);
    expect(find.text(connectionMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timer Dashboard berhenti di tab lain dan aktif saat kembali', (
    tester,
  ) async {
    final dashboard = DashboardStub(() async => null);
    final history = HistoryStub((days) async => []);
    final prediction = PredictionStub();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    await tester.pumpWidget(
      MyApp(
        dashboardService: dashboard,
        historyService: history,
        predictionService: prediction,
      ),
    );
    await tester.pumpAndSettle();

    expect(dashboard.calls, 1);
    expect(history.calls, isEmpty);
    expect(prediction.calls, 0);

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    expect(dashboard.calls, 2);

    await tapText(tester, 'Riwayat');
    expect(history.calls, [7]);

    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();

    expect(dashboard.calls, 2);

    // Tombol kembali dari Riwayat membuka Dashboard.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(dashboard.calls, 3);

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    expect(dashboard.calls, 4);

    await tapText(tester, 'Prediksi');
    expect(prediction.calls, 1);

    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();

    expect(dashboard.calls, 4);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(dashboard.calls, 5);

    for (final label in ['Login', 'Register', 'Profil', 'Rekomendasi']) {
      expect(find.text(label), findsNothing);
    }

    expect(tester.takeException(), isNull);
  });
}
