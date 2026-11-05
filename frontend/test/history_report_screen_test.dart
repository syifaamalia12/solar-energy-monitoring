import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_energy_monitoring/models/history_report.dart';
import 'package:solar_energy_monitoring/models/sensor_reading.dart';
import 'package:solar_energy_monitoring/screens/history_report_screen.dart';
import 'package:solar_energy_monitoring/services/history_report_service.dart';

const selectedDate = '2026-11-05';

class FakeHistoryReportService implements HistoryReportService {
  final dayCalls = <String>[];
  final periodCalls = <String>[];
  final pageCalls = <Map<String, Object?>>[];

  Future<HistoryReport> Function(String date)? onDay;

  Future<HistoryReport> Function(String start, String end)? onPeriod;

  Future<HistoryReadingPage> Function(
    String date,
    int offset,
    String? snapshot,
  )?
  onPage;

  @override
  Future<HistoryReport> fetchDay({required String date}) {
    dayCalls.add(date);
    return onDay?.call(date) ?? Future.value(makeDay(date));
  }

  @override
  Future<HistoryReport> fetchPeriod({
    required String startDate,
    required String endDate,
  }) {
    periodCalls.add('$startDate/$endDate');

    return onPeriod?.call(startDate, endDate) ??
        Future.value(makePeriod(startDate, endDate));
  }

  @override
  Future<HistoryReadingPage> fetchReadingPage({
    required String date,
    int offset = 0,
    String? snapshot,
  }) {
    pageCalls.add({'date': date, 'offset': offset, 'snapshot': snapshot});

    return onPage?.call(date, offset, snapshot) ??
        Future.value(makePage(date, startIndex: 2, length: 1, offset: offset));
  }
}

HistorySummary makeSummary({int count = 149, double energy = 0.29}) {
  return HistorySummary(
    totalEnergyWh: energy,
    readingCount: count,
    averageVoltageV: 4.36,
    averageCurrentA: 0.0266,
    averagePowerW: 0.1168,
  );
}

SensorReading makeReading(String date, int index) {
  return SensorReading(
    readingId: '$date-$index',
    deviceId: 'solar-001',
    timestamp: DateTime.parse('${date}T10:00:00Z')
        .subtract(Duration(minutes: index)),
    voltageV: 4.36,
    currentA: 0.0266,
    powerW: 0.1168,
    energyWh: 0.001,
    intervalSeconds: 60,
  );
}

HistoryReadingPage makePage(
  String date, {
  int startIndex = 0,
  int length = 2,
  int offset = 0,
  int? nextOffset,
  String snapshot = 'snapshot-screen-test',
}) {
  return HistoryReadingPage(
    date: date,
    readings: List.generate(
      length,
      (index) => makeReading(date, startIndex + index),
    ),
    offset: offset,
    nextOffset: nextOffset,
    snapshot: snapshot,
  );
}

HistoryReport makeDay(
  String date, {
  int count = 149,
  double energy = 0.29,
  bool hasMore = false,
}) {
  return HistoryReport(
    startDate: date,
    endDate: date,
    summary: makeSummary(count: count, energy: energy),
    buckets: List.generate(
      24,
      (hour) => HistoryBucket(
        date: date,
        hour: hour,
        totalEnergyWh: hour == 17 ? energy : 0,
        readingCount: hour == 17 ? count : 0,
      ),
    ),
    firstPage: makePage(
      date,
      length: count == 0 ? 0 : 2,
      nextOffset: hasMore ? 100 : null,
    ),
  );
}

HistoryReport makePeriod(String start, String end) {
  final firstDate = DateTime.parse('${start}T00:00:00Z');
  final lastDate = DateTime.parse('${end}T00:00:00Z');
  final length = lastDate.difference(firstDate).inDays + 1;

  return HistoryReport(
    startDate: start,
    endDate: end,
    summary: makeSummary(),
    buckets: List.generate(
      length,
      (index) => HistoryBucket(
        date: firstDate
            .add(Duration(days: index))
            .toIso8601String()
            .substring(0, 10),
        totalEnergyWh: index == 0 ? 0.29 : 0,
        readingCount: index == 0 ? 149 : 0,
      ),
    ),
  );
}

Widget buildApp(HistoryReportService service) {
  return MaterialApp(
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: HistoryReportScreen(
            service: service,
            // 4 November UTC, tetapi sudah 5 November di WIB.
            now: () => DateTime.utc(2026, 11, 4, 18),
          ),
        ),
      ),
    ),
  );
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();

  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String keyedText(WidgetTester tester, String key) {
  return tester.widget<Text>(find.byKey(ValueKey(key))).data!;
}

void main() {
  testWidgets('Awal membuka Harian berdasarkan tanggal WIB', (tester) async {
    final service = FakeHistoryReportService();

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    expect(service.dayCalls, [selectedDate]);
    expect(find.text('5 Nov 2026'), findsOneWidget);
    expect(find.text('Ringkasan Harian'), findsOneWidget);
    expect(find.text('149 pembacaan dalam rekap.'), findsOneWidget);
    expect(keyedText(tester, 'report-total-energy'), '0.2900 Wh');

    final chart = tester.widget<BarChart>(
      find.byKey(const ValueKey('report-chart')),
    );

    expect(chart.data.barGroups, hasLength(24));
    expect(chart.data.barGroups[17].barRods.single.toY, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mingguan memakai Senin sampai Minggu', (tester) async {
    final service = FakeHistoryReportService();

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    await tapVisible(
      tester,
      find.byKey(const ValueKey('report-period-weekly')),
    );

    expect(service.periodCalls, ['2026-11-02/2026-11-08']);
    expect(find.text('Ringkasan Mingguan'), findsOneWidget);
    expect(find.text('2 Nov 2026 – 8 Nov 2026'), findsOneWidget);

    final table = tester.widget<DataTable>(find.byType(DataTable));

    expect(table.rows, hasLength(7));
    expect((table.rows[1].cells[1].child as Text).data, '--');

    // Memilih tab yang sama tidak mengirim permintaan tambahan.
    await tapVisible(
      tester,
      find.byKey(const ValueKey('report-period-weekly')),
    );

    expect(service.periodCalls, hasLength(1));
  });

  testWidgets('Bulanan dan panah sebelumnya menangani 31 hari', (tester) async {
    final service = FakeHistoryReportService();

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    await tapVisible(
      tester,
      find.byKey(const ValueKey('report-period-monthly')),
    );

    expect(service.periodCalls.last, '2026-11-01/2026-11-30');

    await tapVisible(
      tester,
      find.byKey(const ValueKey('report-previous-date')),
    );

    expect(service.periodCalls.last, '2026-10-01/2026-10-31');
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).rows,
      hasLength(31),
    );
    expect(find.text('1 Okt 2026 – 31 Okt 2026'), findsOneWidget);
  });

  testWidgets('Panah berikutnya tidak melewati hari ini', (tester) async {
    final service = FakeHistoryReportService();

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    IconButton nextButton() {
      return tester.widget<IconButton>(
        find.byKey(const ValueKey('report-next-date')),
      );
    }

    expect(nextButton().onPressed, isNull);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('report-previous-date')),
    );

    expect(service.dayCalls.last, '2026-11-04');
    expect(nextButton().onPressed, isNotNull);

    await tapVisible(tester, find.byKey(const ValueKey('report-next-date')));

    expect(service.dayCalls.last, selectedDate);
    expect(nextButton().onPressed, isNull);
  });

  testWidgets('Kalender menggunakan Indonesia dan tanggal terpilih', (
    tester,
  ) async {
    final service = FakeHistoryReportService();

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const ValueKey('report-pick-date')));

    final dialogFinder = find.byType(DatePickerDialog);
    final dialog = tester.widget<DatePickerDialog>(dialogFinder);
    final context = tester.element(dialogFinder);

    expect(Localizations.localeOf(context).languageCode, 'id');
    expect(dialog.initialDate, DateTime(2026, 11, 5));
    expect(dialog.lastDate, DateTime(2026, 11, 5));

    final calendarDay = find.descendant(
      of: find.byType(CalendarDatePicker),
      matching: find.text('2'),
    );

    await tester.tap(calendarDay);
    await tester.pumpAndSettle();

    final confirmLabel = MaterialLocalizations.of(context).okButtonLabel;

    await tester.tap(find.text(confirmLabel));
    await tester.pumpAndSettle();

    expect(service.dayCalls.last, '2026-11-02');
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2 Nov 2026'), findsOneWidget);
  });

  testWidgets('Tidak ada pembacaan berbeda dari energi nol terukur', (
    tester,
  ) async {
    final service = FakeHistoryReportService();
    service.onDay = (date) async => makeDay(date, count: 0, energy: 0);

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-chart')), findsNothing);
    expect(keyedText(tester, 'report-total-energy'), '-- Wh');

    service.onDay = (date) async => makeDay(date, count: 1, energy: 0);

    await tapVisible(tester, find.byKey(const ValueKey('report-refresh')));

    expect(find.byKey(const ValueKey('report-empty')), findsNothing);
    expect(find.byKey(const ValueKey('report-chart')), findsOneWidget);
    expect(keyedText(tester, 'report-total-energy'), '0.0000 Wh');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Muat lebih banyak meneruskan snapshot tanpa mengubah rekap', (
    tester,
  ) async {
    final service = FakeHistoryReportService();
    service.onDay = (date) async => makeDay(date, hasMore: true);

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    expect(
      keyedText(tester, 'report-loaded-count'),
      '2 pembacaan dimuat, terbaru ke terlama.',
    );

    await tapVisible(tester, find.byKey(const ValueKey('report-load-more')));

    expect(service.pageCalls, [
      {'date': selectedDate, 'offset': 100, 'snapshot': 'snapshot-screen-test'},
    ]);
    expect(
      keyedText(tester, 'report-loaded-count'),
      '3 pembacaan dimuat, terbaru ke terlama.',
    );
    expect(find.byKey(const ValueKey('report-load-more')), findsNothing);
    expect(find.text('149 pembacaan dalam rekap.'), findsOneWidget);
    expect(keyedText(tester, 'report-total-energy'), '0.2900 Wh');
  });

  testWidgets(
    'Gagal memuat lanjutan mempertahankan tabel dan bisa dicoba lagi',
    (tester) async {
      final service = FakeHistoryReportService();
      service.onDay = (date) async => makeDay(date, hasMore: true);

      var attempts = 0;

      service.onPage = (date, offset, snapshot) async {
        attempts++;

        if (attempts == 1) {
          throw const HistoryReportApiException(
            'Koneksi terputus saat paging.',
          );
        }

        return makePage(
          date,
          startIndex: 2,
          length: 1,
          offset: offset,
          snapshot: snapshot!,
        );
      };

      await tester.pumpWidget(buildApp(service));
      await tester.pumpAndSettle();

      final more = find.byKey(const ValueKey('report-load-more'));

      await tapVisible(tester, more);

      expect(find.text('Koneksi terputus saat paging.'), findsOneWidget);
      expect(find.text('Coba lagi memuat'), findsOneWidget);
      expect(
        keyedText(tester, 'report-loaded-count'),
        startsWith('2 pembacaan'),
      );

      await tapVisible(tester, more);

      expect(service.pageCalls, hasLength(2));
      expect(service.pageCalls[0], service.pageCalls[1]);
      expect(
        keyedText(tester, 'report-loaded-count'),
        startsWith('3 pembacaan'),
      );
      expect(find.text('Koneksi terputus saat paging.'), findsNothing);
    },
  );

  testWidgets('Pembacaan duplikat dari halaman lanjutan ditolak', (
    tester,
  ) async {
    final service = FakeHistoryReportService();
    service.onDay = (date) async => makeDay(date, hasMore: true);
    service.onPage = (date, offset, snapshot) async {
      return makePage(
        date,
        startIndex: 0,
        length: 1,
        offset: offset,
        snapshot: snapshot!,
      );
    };

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const ValueKey('report-load-more')));

    expect(
      find.text('Ditemukan pembacaan duplikat. Muat ulang riwayat.'),
      findsOneWidget,
    );
    expect(keyedText(tester, 'report-loaded-count'), startsWith('2 pembacaan'));
  });

  testWidgets('Respons Harian lama tidak menimpa periode terbaru', (
    tester,
  ) async {
    final pendingDay = Completer<HistoryReport>();
    final service = FakeHistoryReportService();
    service.onDay = (_) => pendingDay.future;

    await tester.pumpWidget(buildApp(service));

    await tester.tap(find.byKey(const ValueKey('report-period-weekly')));
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan Mingguan'), findsOneWidget);

    pendingDay.complete(makeDay(selectedDate, energy: 99));
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan Mingguan'), findsOneWidget);
    expect(keyedText(tester, 'report-total-energy'), '0.2900 Wh');
    expect(find.byKey(const ValueKey('report-loaded-count')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Respons paging lama diabaikan setelah pindah periode', (
    tester,
  ) async {
    final pendingPage = Completer<HistoryReadingPage>();
    final service = FakeHistoryReportService();

    service.onDay = (date) async => makeDay(date, hasMore: true);
    service.onPage = (_, _, _) => pendingPage.future;

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    final more = find.byKey(const ValueKey('report-load-more'));

    await Scrollable.ensureVisible(tester.element(more));
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pump();

    final weekly = find.byKey(const ValueKey('report-period-weekly'));

    // Ada spinner paging aktif, jadi jangan pumpAndSettle dahulu.
    await Scrollable.ensureVisible(tester.element(weekly));
    await tester.pump();
    await tester.tap(weekly);
    await tester.pumpAndSettle();

    pendingPage.complete(
      makePage(selectedDate, startIndex: 2, length: 1, offset: 100),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan Mingguan'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-loaded-count')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Error sinkron dapat ditampilkan dan dicoba lagi', (
    tester,
  ) async {
    final service = FakeHistoryReportService();
    service.onDay = (_) {
      throw const HistoryReportApiException('Riwayat sedang bermasalah.');
    };

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat sedang bermasalah.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    service.onDay = (date) async => makeDay(date);

    await tapVisible(tester, find.text('Coba lagi'));

    expect(find.text('Ringkasan Harian'), findsOneWidget);
    expect(service.dayCalls, hasLength(2));
  });

  testWidgets('Rentang respons yang berbeda ditolak', (tester) async {
    final service = FakeHistoryReportService();
    service.onDay = (_) async => makeDay('2026-11-02');

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    expect(
      find.text('Rentang data dari server tidak sesuai dengan pilihan.'),
      findsOneWidget,
    );
    expect(find.text('Ringkasan Harian'), findsNothing);
  });

  testWidgets('Respons setelah halaman ditutup tidak memicu exception', (
    tester,
  ) async {
    final pending = Completer<HistoryReport>();
    final service = FakeHistoryReportService();
    service.onDay = (_) => pending.future;

    await tester.pumpWidget(buildApp(service));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    pending.complete(makeDay(selectedDate));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Layar sempit tetap menampilkan kontrol tanpa overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = FakeHistoryReportService();

    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Harian'), findsOneWidget);
    expect(find.text('Mingguan'), findsOneWidget);
    expect(find.text('Bulanan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
