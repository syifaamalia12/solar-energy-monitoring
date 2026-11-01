import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/main.dart';

void main() {
  testWidgets('Aplikasi membuka Dashboard tanpa login', (tester) async {
    await tester.pumpWidget(const MyApp());

    final title = tester.widget<Text>(find.byKey(const ValueKey('page-title')));

    expect(title.data, 'Dashboard Monitoring');
    expect(find.text('Login'), findsNothing);
    expect(find.text('Perangkat: solar-001'), findsOneWidget);
  });

  testWidgets('Navigasi Riwayat dan Prediksi berfungsi', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('page-title'))).data,
      'Riwayat Energi',
    );

    await tester.tap(find.text('Prediksi'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('page-title'))).data,
      'Prediksi Energi',
    );

    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('page-title'))).data,
      'Dashboard Monitoring',
    );
  });

  testWidgets('Tombol kembali menuju Dashboard', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Prediksi'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('page-title'))).data,
      'Dashboard Monitoring',
    );
  });
}
