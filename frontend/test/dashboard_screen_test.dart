import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/screens/dashboard_screen.dart';

void main() {
  testWidgets('Dashboard menampilkan nilai dan label data pengujian', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DashboardScreen())),
      ),
    );

    expect(find.textContaining('Data pengujian'), findsOneWidget);

    expect(find.text('Tegangan'), findsOneWidget);
    expect(find.text('Arus'), findsOneWidget);
    expect(find.text('Daya'), findsOneWidget);
    expect(find.text('Energi harian'), findsOneWidget);

    expect(find.text('5.00 V'), findsOneWidget);
    expect(find.text('0.20 A'), findsOneWidget);
    expect(find.text('1.00 W'), findsOneWidget);
    expect(find.text('0.75 Wh'), findsOneWidget);

    expect(find.text('Waktu pembacaan contoh'), findsOneWidget);
    expect(find.text('Belum terhubung ke API.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
