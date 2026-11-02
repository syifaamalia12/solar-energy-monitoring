import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/models/daily_energy.dart';
import 'package:solar_energy_monitoring/screens/history_screen.dart';
import 'package:solar_energy_monitoring/services/history_service.dart';
import 'package:solar_energy_monitoring/utils/measurement_format.dart';

class TestHistoryService implements HistoryService {
  TestHistoryService(this.handler);

  final Future<List<DailyEnergy>> Function(int days) handler;
  final List<int> calls = [];

  @override
  Future<List<DailyEnergy>> fetchHistory({required int days}) {
    calls.add(days);
    return handler(days);
  }
}

DailyEnergy sample({String date = '2026-10-29', double energy = 0.00001952}) {
  return DailyEnergy(date: date, totalEnergyWh: energy, readingCount: 8);
}

Widget buildTestApp(HistoryService service) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: HistoryScreen(service: service),
      ),
    ),
  );
}

BarChart getChart(WidgetTester tester) {
  return tester.widget<BarChart>(find.byKey(const ValueKey('history-chart')));
}

void main() {
  testWidgets('Menampilkan loading selama menunggu riwayat', (tester) async {
    final completer = Completer<List<DailyEnergy>>();
    final service = TestHistoryService((days) => completer.future);

    await tester.pumpWidget(buildTestApp(service));

    expect(find.text('Memuat riwayat energi...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);

    completer.complete([]);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Data kosong tidak menampilkan grafik atau nol buatan', (
    tester,
  ) async {
    final service = TestHistoryService((days) async => []);

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(
      find.text('Riwayat energi belum tersedia untuk 7 hari terakhir.'),
      findsOneWidget,
    );
    expect(find.byType(BarChart), findsNothing);
    expect(find.text('0.0000 Wh'), findsNothing);
    expect(find.text('Muat ulang'), findsOneWidget);
  });

  testWidgets('Satu data menampilkan tanggal, Wh, dan satu batang', (
    tester,
  ) async {
    final service = TestHistoryService((days) async => [sample()]);

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(service.calls, [7]);
    expect(find.text('29/10/2026 WIB'), findsOneWidget);
    expect(find.text('8 pembacaan'), findsOneWidget);
    expect(find.text('${formatMeasurement(0.00001952)} Wh'), findsOneWidget);

    final chart = getChart(tester);

    expect(chart.data.barGroups, hasLength(1));
    expect(chart.data.barGroups.single.barRods.single.toY, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pilihan periode meminta 7, 14, dan 30 hari', (tester) async {
    final service = TestHistoryService((days) async => [sample()]);

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-period-14')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('history-period-14')))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('history-period-30')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('history-period-30')))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('history-period-7')));
    await tester.pumpAndSettle();

    expect(service.calls, [7, 14, 30, 7]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Coba lagi mengambil ulang periode yang gagal', (tester) async {
    var attempts = 0;

    final service = TestHistoryService((days) async {
      attempts++;

      if (attempts == 1) {
        throw const HistoryApiException(
          'Tidak dapat terhubung ke server. Periksa koneksi internet.',
        );
      }

      return [sample()];
    });

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(
      find.text('Tidak dapat terhubung ke server. Periksa koneksi internet.'),
      findsOneWidget,
    );
    expect(find.byType(BarChart), findsNothing);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(service.calls, [7, 7]);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Coba lagi'), findsNothing);
  });

  testWidgets('Energi nol tetap tampil dan tidak menyebabkan error grafik', (
    tester,
  ) async {
    final service = TestHistoryService((days) async => [sample(energy: 0)]);

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(find.text('0.0000 Wh'), findsOneWidget);
    expect(
      find.text(
        'Seluruh energi yang tercatat bernilai 0 Wh. '
        'Batang berada pada garis dasar grafik.',
      ),
      findsOneWidget,
    );

    final chart = getChart(tester);

    expect(chart.data.barGroups, hasLength(1));
    expect(chart.data.barGroups.single.barRods.single.toY, 0);
    expect(chart.data.maxY, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tanggal yang tidak tersedia tidak ditambahkan ke grafik', (
    tester,
  ) async {
    final service = TestHistoryService(
      (days) async => [
        sample(date: '2026-10-29', energy: 1),
        sample(date: '2026-11-02', energy: 2),
      ],
    );

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    expect(find.text('29/10/2026 WIB'), findsOneWidget);
    expect(find.text('02/11/2026 WIB'), findsOneWidget);
    expect(find.text('30/10/2026 WIB'), findsNothing);
    expect(find.text('31/10/2026 WIB'), findsNothing);
    expect(find.text('01/11/2026 WIB'), findsNothing);

    final chart = getChart(tester);

    expect(chart.data.barGroups, hasLength(2));
    expect(chart.data.barGroups[0].barRods.single.toY, 0.5);
    expect(chart.data.barGroups[1].barRods.single.toY, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Muat ulang menggunakan periode yang sedang dipilih', (
    tester,
  ) async {
    final service = TestHistoryService((days) async => []);

    await tester.pumpWidget(buildTestApp(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-period-30')));
    await tester.pumpAndSettle();

    expect(
      find.text('Riwayat energi belum tersedia untuk 30 hari terakhir.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Muat ulang'));
    await tester.pumpAndSettle();

    expect(service.calls, [7, 30, 30]);
  });

  testWidgets('Respons periode lama tidak menimpa periode terbaru', (
    tester,
  ) async {
    final sevenDays = Completer<List<DailyEnergy>>();
    final fourteenDays = Completer<List<DailyEnergy>>();

    final service = TestHistoryService((days) {
      return days == 7 ? sevenDays.future : fourteenDays.future;
    });

    await tester.pumpWidget(buildTestApp(service));

    await tester.tap(find.byKey(const ValueKey('history-period-14')));
    await tester.pump();

    fourteenDays.complete([sample(date: '2026-11-02', energy: 2)]);
    await tester.pumpAndSettle();

    expect(find.text('02/11/2026 WIB'), findsOneWidget);

    // Request 7 hari selesai belakangan.
    sevenDays.complete([sample(date: '2026-10-29', energy: 1)]);
    await tester.pumpAndSettle();

    expect(find.text('02/11/2026 WIB'), findsOneWidget);
    expect(find.text('29/10/2026 WIB'), findsNothing);
    expect(service.calls, [7, 14]);
    expect(tester.takeException(), isNull);
  });
}
