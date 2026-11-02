import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/models/energy_prediction.dart';
import 'package:solar_energy_monitoring/screens/prediction_screen.dart';
import 'package:solar_energy_monitoring/services/prediction_service.dart';

class TestPredictionService implements PredictionService {
  TestPredictionService(this.handler);

  final Future<EnergyPrediction?> Function() handler;
  int calls = 0;

  @override
  Future<EnergyPrediction?> fetchLatestPrediction() {
    calls++;
    return handler();
  }
}

EnergyPrediction sample({String date = '2026-11-02', double energy = 0.75}) {
  return EnergyPrediction(
    deviceId: 'solar-001',
    predictionDate: date,
    predictedEnergyWh: energy,
    modelName: 'Linear Regression',
    createdAt: DateTime.parse('2026-10-31T18:57:10.231Z'),
  );
}

Widget buildTestApp(PredictionService service) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: PredictionScreen(service: service),
      ),
    ),
  );
}

String textAt(WidgetTester tester, String key) {
  return tester.widget<Text>(find.byKey(ValueKey(key))).data!;
}

Future<void> tapRefresh(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('prediction-refresh'));

  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Menampilkan nilai, tanggal, model, dan waktu WIB', (
    tester,
  ) async {
    final service = TestPredictionService(() async => sample());

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(textAt(tester, 'page-title'), 'Prediksi Energi');
    expect(textAt(tester, 'prediction-energy'), '0.7500 Wh');
    expect(textAt(tester, 'prediction-target-date'), '02/11/2026');
    expect(textAt(tester, 'prediction-model'), 'Linear Regression');
    expect(textAt(tester, 'prediction-created-at'), '01/11/2026, 01:57:10 WIB');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menampilkan loading selama menunggu prediksi', (tester) async {
    final completer = Completer<EnergyPrediction?>();
    final service = TestPredictionService(() => completer.future);

    await tester.pumpWidget(buildTestApp(service));

    expect(find.text('Memuat prediksi energi...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('prediction-energy')), findsNothing);

    completer.complete(null);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Prediksi kosong bukan error dan bukan nilai nol', (
    tester,
  ) async {
    final service = TestPredictionService(() async => null);

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Prediksi energi belum tersedia.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsNothing);
    expect(find.text('Muat ulang'), findsOneWidget);
    expect(find.text('0.0000 Wh'), findsNothing);
    expect(find.byKey(const ValueKey('prediction-target-date')), findsNothing);
  });

  testWidgets('Nilai prediksi nol tetap ditampilkan sebagai data', (
    tester,
  ) async {
    final service = TestPredictionService(() async => sample(energy: 0));

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(textAt(tester, 'prediction-energy'), '0.0000 Wh');
    expect(textAt(tester, 'prediction-target-date'), '02/11/2026');
    expect(find.text('Prediksi energi belum tersedia.'), findsNothing);
  });

  testWidgets('Tanggal target lama tetap mengikuti hasil backend', (
    tester,
  ) async {
    final service = TestPredictionService(
      () async => sample(date: '2025-01-15'),
    );

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(textAt(tester, 'prediction-target-date'), '15/01/2025');
    expect(
      find.text(
        'Tanggal target mengikuti hasil backend, '
        'tidak selalu untuk besok.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Muat ulang memperbarui nilai dan tanggal target', (
    tester,
  ) async {
    var attempts = 0;
    final service = TestPredictionService(() async {
      attempts++;

      return attempts == 1
          ? sample()
          : sample(date: '2026-11-05', energy: 1.25);
    });

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(textAt(tester, 'prediction-energy'), '0.7500 Wh');

    await tapRefresh(tester);

    expect(service.calls, 2);
    expect(textAt(tester, 'prediction-energy'), '1.2500 Wh');
    expect(textAt(tester, 'prediction-target-date'), '05/11/2026');
    expect(find.text('0.7500 Wh'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Coba lagi memulihkan tampilan setelah koneksi gagal', (
    tester,
  ) async {
    var attempts = 0;
    final service = TestPredictionService(() async {
      attempts++;

      if (attempts == 1) {
        throw const PredictionApiException(
          'Tidak dapat terhubung ke server. Periksa koneksi internet.',
        );
      }

      return sample();
    });

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(
      find.text('Tidak dapat terhubung ke server. Periksa koneksi internet.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('prediction-energy')), findsNothing);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(service.calls, 2);
    expect(textAt(tester, 'prediction-energy'), '0.7500 Wh');
    expect(find.text('Coba lagi'), findsNothing);
  });

  testWidgets('Muat ulang dapat mengambil prediksi setelah data kosong', (
    tester,
  ) async {
    var attempts = 0;
    final service = TestPredictionService(() async {
      attempts++;
      return attempts == 1 ? null : sample();
    });

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Prediksi energi belum tersedia.'), findsOneWidget);

    await tapRefresh(tester);

    expect(service.calls, 2);
    expect(textAt(tester, 'prediction-energy'), '0.7500 Wh');
    expect(find.text('Prediksi energi belum tersedia.'), findsNothing);
  });

  testWidgets('Kegagalan refresh tidak menampilkan hasil lama sebagai baru', (
    tester,
  ) async {
    var attempts = 0;
    final service = TestPredictionService(() async {
      attempts++;

      if (attempts > 1) {
        throw const PredictionApiException(
          'Waktu permintaan habis. Silakan coba lagi.',
        );
      }

      return sample();
    });

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    await tapRefresh(tester);

    expect(service.calls, 2);
    expect(
      find.text('Waktu permintaan habis. Silakan coba lagi.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('prediction-energy')), findsNothing);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
