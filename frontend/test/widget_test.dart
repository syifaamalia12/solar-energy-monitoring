import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/main.dart';

Future<void> openApp(WidgetTester tester) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });

  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();
}

String? pageTitle(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(const ValueKey('page-title'))).data;
}

void main() {
  testWidgets('Aplikasi membuka Dashboard tanpa login', (tester) async {
    await openApp(tester);

    expect(pageTitle(tester), 'Dashboard Monitoring');
    expect(find.text('Login'), findsNothing);
    expect(find.text('Perangkat: solar-001'), findsOneWidget);
  });

  testWidgets('Navigasi Riwayat dan Prediksi berfungsi', (tester) async {
    await openApp(tester);

    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(pageTitle(tester), 'Riwayat Energi');

    await tester.tap(find.text('Prediksi'));
    await tester.pumpAndSettle();
    expect(pageTitle(tester), 'Prediksi Energi');

    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(pageTitle(tester), 'Dashboard Monitoring');
  });

  testWidgets('Tombol kembali menuju Dashboard', (tester) async {
    await openApp(tester);

    await tester.tap(find.text('Prediksi'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(pageTitle(tester), 'Dashboard Monitoring');
  });
}
