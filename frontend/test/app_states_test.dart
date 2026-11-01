import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/widgets/app_states.dart';

Widget testApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('Menampilkan indikator saat memuat data', (tester) async {
    await tester.pumpWidget(testApp(const AppLoading()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Memuat data...'), findsOneWidget);
  });

  testWidgets('Menampilkan pesan saat data kosong', (tester) async {
    await tester.pumpWidget(
      testApp(const AppEmptyState(message: 'Prediksi belum tersedia.')),
    );

    expect(find.text('Prediksi belum tersedia.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Tombol coba lagi menjalankan permintaan ulang', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      testApp(
        AppErrorState(
          onRetry: () {
            retryCount++;
          },
        ),
      ),
    );

    expect(find.text('Data gagal dimuat. Silakan coba lagi.'), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    await tester.pump();

    expect(retryCount, 1);
  });
}
