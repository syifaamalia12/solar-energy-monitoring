import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/models/dashboard_data.dart';
import 'package:solar_energy_monitoring/models/energy_prediction.dart';
import 'package:solar_energy_monitoring/screens/dashboard_screen.dart';
import 'package:solar_energy_monitoring/screens/main_screen.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';
import 'package:solar_energy_monitoring/services/prediction_service.dart';

class HomeDashboardStub implements DashboardService {
  int calls = 0;

  @override
  Future<DashboardData?> fetchDashboard() async {
    calls++;

    return DashboardData(
      deviceId: 'solar-001',
      voltageV: 5,
      currentA: 0.5,
      powerW: 2.5,
      totalEnergyWh: 2,
      summaryDate: '2026-11-02',
      readingTimestamp: DateTime.utc(2026, 11, 2, 10),
      isTestData: true,
      readingCount: 8,
    );
  }
}

class HomePredictionStub implements PredictionService {
  HomePredictionStub(this.handler);

  final Future<EnergyPrediction?> Function() handler;
  int calls = 0;

  @override
  Future<EnergyPrediction?> fetchLatestPrediction() {
    calls++;
    return handler();
  }
}

EnergyPrediction samplePrediction({
  double energy = 0.75,
  String date = '2026-11-05',
}) {
  return EnergyPrediction(
    deviceId: 'solar-001',
    predictionDate: date,
    predictedEnergyWh: energy,
    modelName: 'Linear Regression',
    createdAt: DateTime.utc(2026, 11, 4, 1),
  );
}

Future<void> openHome(
  WidgetTester tester, {
  required HomeDashboardStub dashboard,
  required HomePredictionStub prediction,
  bool withNavigation = false,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  await tester.pumpWidget(
    MaterialApp(
      home: withNavigation
          ? MainScreen(
              dashboardService: dashboard,
              predictionService: prediction,
            )
          : Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: DashboardScreen(
                  service: dashboard,
                  predictionService: prediction,
                ),
              ),
            ),
    ),
  );

  // Jangan pumpAndSettle di sini:
  // tes loading memakai Future yang sengaja belum selesai.
  await tester.pump();
}

String keyedText(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);

  return tester.widget<Text>(finder).data!;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));

  await tester.scrollUntilVisible(
    finder.hitTestable(),
    150,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();

  expect(finder.hitTestable(), findsOneWidget);

  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ringkasan menampilkan loading tanpa menutupi monitoring', (
    tester,
  ) async {
    final pending = Completer<EnergyPrediction?>();
    final dashboard = HomeDashboardStub();
    final prediction = HomePredictionStub(() => pending.future);

    await openHome(tester, dashboard: dashboard, prediction: prediction);
    await tester.pump();

    expect(find.text('Memuat ringkasan prediksi...'), findsOneWidget);
    expect(find.text('5.00 V'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-prediction-energy')), findsNothing);

    pending.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Memuat ringkasan prediksi...'), findsNothing);
    expect(find.byKey(const ValueKey('home-prediction-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ringkasan menampilkan nilai dan tanggal dari layanan', (
    tester,
  ) async {
    final dashboard = HomeDashboardStub();
    final prediction = HomePredictionStub(() async => samplePrediction());

    await openHome(tester, dashboard: dashboard, prediction: prediction);
    await tester.pumpAndSettle();

    expect(prediction.calls, 1);
    expect(keyedText(tester, 'home-prediction-energy'), '0.7500 Wh');
    expect(
      keyedText(tester, 'home-prediction-target-date'),
      'Tanggal target: 05/11/2026',
    );
    expect(find.text('Model: Linear Regression'), findsOneWidget);
    expect(
      find.text(
        'Tanggal target mengikuti hasil backend, '
        'tidak selalu untuk besok.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Prediksi nol tetap ditampilkan sebagai data', (tester) async {
    final dashboard = HomeDashboardStub();
    final prediction = HomePredictionStub(
      () async => samplePrediction(energy: 0),
    );

    await openHome(tester, dashboard: dashboard, prediction: prediction);
    await tester.pumpAndSettle();

    expect(keyedText(tester, 'home-prediction-energy'), '0.0000 Wh');
    expect(find.byKey(const ValueKey('home-prediction-empty')), findsNothing);
  });

  testWidgets('Prediksi kosong tidak dibuat menjadi nilai nol', (tester) async {
    final dashboard = HomeDashboardStub();
    final prediction = HomePredictionStub(() async => null);

    await openHome(tester, dashboard: dashboard, prediction: prediction);
    await tester.pumpAndSettle();

    expect(
      keyedText(tester, 'home-prediction-empty'),
      'Prediksi energi belum tersedia.',
    );
    expect(find.byKey(const ValueKey('home-prediction-energy')), findsNothing);
    expect(find.text('0.0000 Wh'), findsNothing);
    expect(find.text('5.00 V'), findsOneWidget);
  });

  testWidgets(
    'Error prediksi tidak menghilangkan monitoring dan bisa diulang',
    (tester) async {
      final dashboard = HomeDashboardStub();
      var attempts = 0;

      final prediction = HomePredictionStub(() {
        attempts++;

        if (attempts == 1) {
          throw const PredictionApiException(
            'Tidak dapat terhubung ke server. Periksa koneksi internet.',
          );
        }

        return Future.value(samplePrediction());
      });

      await openHome(tester, dashboard: dashboard, prediction: prediction);
      await tester.pumpAndSettle();

      expect(find.text('Ringkasan prediksi gagal dimuat.'), findsOneWidget);
      expect(find.text('5.00 V'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapKey(tester, 'home-prediction-retry');

      expect(prediction.calls, 2);
      expect(dashboard.calls, 1);
      expect(keyedText(tester, 'home-prediction-energy'), '0.7500 Wh');
      expect(find.text('Ringkasan prediksi gagal dimuat.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Muat ulang Beranda memperbarui ringkasan prediksi', (
    tester,
  ) async {
    final dashboard = HomeDashboardStub();
    var attempts = 0;

    final prediction = HomePredictionStub(() async {
      attempts++;

      return attempts == 1
          ? samplePrediction()
          : samplePrediction(energy: 1.25, date: '2026-11-06');
    });

    await openHome(tester, dashboard: dashboard, prediction: prediction);
    await tester.pumpAndSettle();

    expect(keyedText(tester, 'home-prediction-energy'), '0.7500 Wh');

    final refresh = find.widgetWithText(OutlinedButton, 'Muat ulang');

    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();

    expect(dashboard.calls, 2);
    expect(prediction.calls, 2);
    expect(keyedText(tester, 'home-prediction-energy'), '1.2500 Wh');
    expect(
      keyedText(tester, 'home-prediction-target-date'),
      'Tanggal target: 06/11/2026',
    );
    expect(find.text('0.7500 Wh'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lihat prediksi membuka tab Prediksi dari Beranda', (
    tester,
  ) async {
    final dashboard = HomeDashboardStub();
    final prediction = HomePredictionStub(() async => null);

    await openHome(
      tester,
      dashboard: dashboard,
      prediction: prediction,
      withNavigation: true,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-prediction-card')), findsOneWidget);

    await tapKey(tester, 'home-open-prediction');

    expect(keyedText(tester, 'page-title'), 'Prediksi Energi');

    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));

    expect(navigation.selectedIndex, 2);
    expect(find.byKey(const ValueKey('home-prediction-card')), findsNothing);
    expect(find.text('Prediksi energi belum tersedia.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
