import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/models/dashboard_data.dart';
import 'package:solar_energy_monitoring/screens/dashboard_screen.dart';
import 'package:solar_energy_monitoring/services/dashboard_service.dart';

class TestDashboardService implements DashboardService {
  TestDashboardService(this.handler);

  final Future<DashboardData?> Function() handler;

  @override
  Future<DashboardData?> fetchDashboard() => handler();
}

Widget buildTestApp({DashboardService? service}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DashboardScreen(service: service)),
    ),
  );
}

void main() {
  testWidgets('Dashboard menampilkan data pengujian', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Data pengujian'), findsOneWidget);

    expect(find.text('Tegangan'), findsOneWidget);
    expect(find.text('Arus'), findsOneWidget);
    expect(find.text('Daya'), findsOneWidget);
    expect(find.text('Energi harian'), findsOneWidget);

    expect(find.text('5.00 V'), findsOneWidget);
    expect(find.text('0.2000 A'), findsOneWidget);
    expect(find.text('1.0000 W'), findsOneWidget);
    expect(find.text('0.7500 Wh'), findsOneWidget);

    expect(find.text('Tanggal rekap energi (WIB): 2026-11-01'), findsOneWidget);
    expect(find.text('01/11/2026, 12:00 WIB'), findsOneWidget);
    expect(find.text('Belum terhubung ke API.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard menampilkan loading saat menunggu data', (
    tester,
  ) async {
    final completer = Completer<DashboardData?>();
    final service = TestDashboardService(() => completer.future);

    await tester.pumpWidget(buildTestApp(service: service));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Memuat data...'), findsOneWidget);

    completer.complete(null);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Dashboard menampilkan pesan saat data kosong', (tester) async {
    final service = TestDashboardService(() async => null);

    await tester.pumpWidget(buildTestApp(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Data monitoring belum tersedia.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(find.text('5.00 V'), findsNothing);
  });

  testWidgets('Tombol coba lagi memuat data setelah error', (tester) async {
    var calls = 0;
    final mock = MockDashboardService(deviceId: 'solar-001');

    final service = TestDashboardService(() async {
      calls++;

      if (calls == 1) {
        throw Exception('Kesalahan simulasi');
      }

      return mock.fetchDashboard();
    });

    await tester.pumpWidget(buildTestApp(service: service));
    await tester.pumpAndSettle();

    expect(
      find.text('Data monitoring gagal dimuat. Silakan coba lagi.'),
      findsOneWidget,
    );
    expect(find.text('5.00 V'), findsNothing);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('5.00 V'), findsOneWidget);
    expect(
      find.text('Data monitoring gagal dimuat. Silakan coba lagi.'),
      findsNothing,
    );
  });
}
