import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solar_energy_monitoring/models/history_report.dart';
import 'package:solar_energy_monitoring/services/history_report_service.dart';

const testDate = '2026-11-02';
const testDevice = 'solar-001';

Map<String, dynamic> summaryJson({
  double energy = 0.29007337,
  int count = 149,
}) {
  return {
    'total_energy_wh': energy,
    'reading_count': count,
    'avg_voltage_v': 4.36,
    'avg_current_a': 0.0266,
    'avg_power_w': 0.1168,
  };
}

Map<String, dynamic> readingJson(int index) {
  return {
    'reading_id': 'reading-$index',
    'device_id': testDevice,
    'timestamp': DateTime.utc(
      2026,
      11,
      2,
      10,
    ).subtract(Duration(minutes: index)).toIso8601String(),
    'voltage_v': 4.36,
    'current_a': 0.0266,
    'power_w': 0.1168,
    'energy_wh': 0.001,
    'interval_seconds': 60,
  };
}

Map<String, dynamic> pageJson({
  int offset = 0,
  int length = 100,
  bool hasMore = true,
  String snapshot = 'snapshot-test',
}) {
  return {
    'device_id': testDevice,
    'date': testDate,
    'limit': 100,
    'offset': offset,
    'count': length,
    'has_more': hasMore,
    'next_offset': hasMore ? offset + 100 : null,
    'snapshot': snapshot,
    'data': List.generate(length, (index) => readingJson(offset + index)),
  };
}

Map<String, dynamic> responseFor(http.Request request) {
  final endpoint = request.url.pathSegments.last;
  final parameters = request.url.queryParameters;

  switch (endpoint) {
    case 'history':
      final offset = int.parse(parameters['offset']!);

      return pageJson(
        offset: offset,
        length: offset == 0 ? 100 : 49,
        hasMore: offset == 0,
      );

    case 'daily-summary':
      return {
        'device_id': testDevice,
        'timezone': 'Asia/Jakarta',
        'data': {'date': testDate, ...summaryJson()},
      };

    case 'hourly-summary':
      return {
        'device_id': testDevice,
        'timezone': 'Asia/Jakarta',
        'date': testDate,
        'count': 24,
        'data': List.generate(
          24,
          (hour) => {
            'hour': hour,
            'total_energy_wh': hour == 16 ? 0.29007337 : 0,
            'reading_count': hour == 16 ? 149 : 0,
          },
        ),
      };

    case 'daily-history':
      final start = DateTime.parse('${parameters['start_date']}T00:00:00Z');
      final end = DateTime.parse('${parameters['end_date']}T00:00:00Z');
      final days = end.difference(start).inDays + 1;

      return {
        'device_id': testDevice,
        'timezone': 'Asia/Jakarta',
        'start_date': parameters['start_date'],
        'end_date': parameters['end_date'],
        'count': days,
        'data': List.generate(
          days,
          (index) => {
            'date': start
                .add(Duration(days: index))
                .toIso8601String()
                .substring(0, 10),
            'total_energy_wh': index == 0 ? 0.29007337 : 0,
            'reading_count': index == 0 ? 149 : 0,
          },
        ),
      };

    case 'period-summary':
      return {
        'device_id': testDevice,
        'timezone': 'Asia/Jakarta',
        'start_date': parameters['start_date'],
        'end_date': parameters['end_date'],
        'data': summaryJson(),
      };

    default:
      throw StateError('Endpoint tidak diharapkan: $endpoint');
  }
}

ApiHistoryReportService createService(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = MockClient(handler);
  addTearDown(client.close);

  return ApiHistoryReportService(
    baseUrl: 'https://example.test/',
    deviceId: testDevice,
    client: client,
  );
}

http.Response jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('Model Riwayat', () {
    test('Tanggal kabisat valid diterima', () {
      expect(validateHistoryDate('2024-02-29'), '2024-02-29');
    });

    test('Tanggal tidak valid ditolak', () {
      for (final value in [
        '2026-02-29',
        '2026-11-31',
        '2026-13-01',
        '0000-01-01',
        '02-11-2026',
        null,
      ]) {
        expect(() => validateHistoryDate(value), throwsFormatException);
      }
    });

    test('Angka negatif, bukan angka, dan tidak finite ditolak', () {
      for (final value in [-1, double.nan, double.infinity, '0.29', null]) {
        expect(() => historyNumber(value), throwsFormatException);
      }
    });

    test('Jumlah pembacaan harus bilangan bulat nonnegatif', () {
      expect(historyCount(0), 0);
      expect(historyCount(149), 149);

      for (final value in [-1, 1.5, '149', null]) {
        expect(() => historyCount(value), throwsFormatException);
      }
    });

    test('Energi nol dengan pembacaan berbeda dari tidak ada data', () {
      final measuredZero = HistorySummary.fromJson(
        summaryJson(energy: 0, count: 1),
      );
      final missing = HistorySummary.fromJson(summaryJson(energy: 0, count: 0));

      expect(measuredZero.totalEnergyWh, 0);
      expect(measuredZero.hasReadings, isTrue);
      expect(missing.hasReadings, isFalse);
    });

    test('Jam hanya boleh 0 sampai 23', () {
      for (final hour in [-1, 24, 1.5, '12', null]) {
        expect(
          () => HistoryBucket.hourly({
            'hour': hour,
            'total_energy_wh': 0,
            'reading_count': 0,
          }, date: testDate),
          throwsFormatException,
        );
      }
    });
  });

  group('API Riwayat Harian', () {
    test('Memakai tiga endpoint dan rekap seluruh pembacaan', () async {
      final endpoints = <String>[];
      final service = createService((request) async {
        endpoints.add(request.url.pathSegments.last);

        expect(request.method, 'GET');
        expect(request.url.queryParameters['device_id'], testDevice);
        expect(request.url.queryParameters['date'], testDate);
        expect(request.headers.containsKey('authorization'), isFalse);

        return jsonResponse(responseFor(request));
      });

      final report = await service.fetchDay(date: testDate);

      expect(
        endpoints,
        unorderedEquals(['daily-summary', 'hourly-summary', 'history']),
      );
      expect(report.startDate, testDate);
      expect(report.endDate, testDate);
      expect(report.buckets, hasLength(24));
      expect(
        report.buckets.map((bucket) => bucket.hour),
        orderedEquals(List.generate(24, (hour) => hour)),
      );
      expect(report.summary.readingCount, 149);
      expect(report.summary.totalEnergyWh, closeTo(0.29007337, 1e-10));

      // Rekap 149 pembacaan, walaupun tabel baru memuat 100.
      expect(report.firstPage!.readings, hasLength(100));
      expect(report.firstPage!.hasMore, isTrue);
      expect(report.buckets.first.hasReadings, isFalse);
    });

    test('Halaman berikutnya memakai snapshot dan next_offset', () async {
      final requests = <http.Request>[];
      final service = createService((request) async {
        requests.add(request);
        return jsonResponse(responseFor(request));
      });

      final first = await service.fetchReadingPage(date: testDate);
      final second = await service.fetchReadingPage(
        date: testDate,
        offset: first.nextOffset!,
        snapshot: first.snapshot,
      );

      expect(requests.first.url.queryParameters['limit'], '100');
      expect(requests.first.url.queryParameters['offset'], '0');
      expect(
        requests.first.url.queryParameters.containsKey('snapshot'),
        isFalse,
      );
      expect(requests.last.url.queryParameters['offset'], '100');
      expect(requests.last.url.queryParameters['snapshot'], first.snapshot);

      expect(first.readings.length + second.readings.length, 149);
      expect(second.hasMore, isFalse);
      expect(second.nextOffset, isNull);

      final ids = [
        ...first.readings,
        ...second.readings,
      ].map((reading) => reading.readingId);

      expect(ids.toSet(), hasLength(149));
    });

    test('Offset lanjutan tanpa snapshot ditolak sebelum HTTP', () async {
      var calls = 0;
      final service = createService((request) async {
        calls++;
        return jsonResponse(responseFor(request));
      });

      await expectLater(
        service.fetchReadingPage(date: testDate, offset: 100),
        throwsArgumentError,
      );
      expect(calls, 0);
    });

    test('Snapshot yang berubah ditolak', () async {
      final service = createService((request) async {
        return jsonResponse(
          pageJson(
            offset: 100,
            length: 49,
            hasMore: false,
            snapshot: 'snapshot-berbeda',
          ),
        );
      });

      await expectLater(
        service.fetchReadingPage(
          date: testDate,
          offset: 100,
          snapshot: 'snapshot-test',
        ),
        throwsA(isA<HistoryReportApiException>()),
      );
    });

    for (final invalidCase in [
      'count',
      'next_offset',
      'duplicate_id',
      'wrong_day',
      'wrong_device',
      'wrong_order',
    ]) {
      test('Respons halaman tidak valid ditolak: $invalidCase', () async {
        final service = createService((request) async {
          final body = pageJson();
          final rows = body['data'] as List<Map<String, dynamic>>;

          switch (invalidCase) {
            case 'count':
              body['count'] = 99;
              break;
            case 'next_offset':
              body['next_offset'] = 50;
              break;
            case 'duplicate_id':
              rows[1]['reading_id'] = rows[0]['reading_id'];
              break;
            case 'wrong_day':
              rows[0]['timestamp'] = '2026-11-01T10:00:00Z';
              break;
            case 'wrong_device':
              rows[0]['device_id'] = 'perangkat-lain';
              break;
            case 'wrong_order':
              final first = rows[0];
              rows[0] = rows[1];
              rows[1] = first;
              break;
          }

          return jsonResponse(body);
        });

        await expectLater(
          service.fetchReadingPage(date: testDate),
          throwsA(isA<HistoryReportApiException>()),
        );
      });
    }

    test('Tanggal pembacaan menggunakan WIB, bukan tanggal UTC', () async {
      final service = createService((request) async {
        final body = pageJson(length: 1, hasMore: false);
        final rows = body['data'] as List<Map<String, dynamic>>;

        // 1 November 17.30 UTC = 2 November 00.30 WIB.
        rows.single['timestamp'] = '2026-11-01T17:30:00Z';

        return jsonResponse(body);
      });

      final page = await service.fetchReadingPage(date: testDate);
      expect(page.readings, hasLength(1));
    });

    for (final invalidCase in ['missing_hour', 'duplicate_hour', 'timezone']) {
      test('Rekap jam tidak valid ditolak: $invalidCase', () async {
        final service = createService((request) async {
          final body = responseFor(request);

          if (request.url.pathSegments.last == 'hourly-summary') {
            final rows = body['data'] as List<Map<String, dynamic>>;

            switch (invalidCase) {
              case 'missing_hour':
                rows.removeLast();
                body['count'] = rows.length;
                break;
              case 'duplicate_hour':
                rows[1]['hour'] = 0;
                break;
              case 'timezone':
                body['timezone'] = 'UTC';
                break;
            }
          }

          return jsonResponse(body);
        });

        await expectLater(
          service.fetchDay(date: testDate),
          throwsA(isA<HistoryReportApiException>()),
        );
      });
    }
  });

  group('API Riwayat Mingguan dan Bulanan', () {
    test('Rentang inklusif dan tanggal tanpa data tetap disimpan', () async {
      final requests = <http.Request>[];
      final service = createService((request) async {
        requests.add(request);
        return jsonResponse(responseFor(request));
      });

      final report = await service.fetchPeriod(
        startDate: '2026-11-02',
        endDate: '2026-11-08',
      );

      expect(
        requests.map((request) => request.url.pathSegments.last),
        unorderedEquals(['daily-history', 'period-summary']),
      );

      for (final request in requests) {
        expect(request.url.queryParameters['start_date'], '2026-11-02');
        expect(request.url.queryParameters['end_date'], '2026-11-08');
        expect(request.url.queryParameters.containsKey('days'), isFalse);
      }

      expect(report.buckets, hasLength(7));
      expect(report.buckets.first.date, '2026-11-02');
      expect(report.buckets.last.date, '2026-11-08');
      expect(report.buckets[1].hasReadings, isFalse);
      expect(report.summary.readingCount, 149);
      expect(report.firstPage, isNull);
    });

    test('Bulan dengan 31 hari tidak dipotong menjadi 30 hari', () async {
      final service = createService((request) async {
        return jsonResponse(responseFor(request));
      });

      final report = await service.fetchPeriod(
        startDate: '2026-10-01',
        endDate: '2026-10-31',
      );

      expect(report.buckets, hasLength(31));
      expect(report.buckets.last.date, '2026-10-31');
    });

    test('Februari tahun kabisat memuat 29 hari', () async {
      final service = createService((request) async {
        return jsonResponse(responseFor(request));
      });

      final report = await service.fetchPeriod(
        startDate: '2024-02-01',
        endDate: '2024-02-29',
      );

      expect(report.buckets, hasLength(29));
    });

    test('Rentang terbalik dan lebih dari 366 hari ditolak', () async {
      var calls = 0;
      final service = createService((request) async {
        calls++;
        return jsonResponse(responseFor(request));
      });

      await expectLater(
        service.fetchPeriod(startDate: '2026-11-08', endDate: '2026-11-02'),
        throwsArgumentError,
      );

      await expectLater(
        service.fetchPeriod(startDate: '2025-01-01', endDate: '2026-01-02'),
        throwsArgumentError,
      );

      expect(calls, 0);
    });

    test('Tanggal rekap yang terduplikasi ditolak', () async {
      final service = createService((request) async {
        final body = responseFor(request);

        if (request.url.pathSegments.last == 'daily-history') {
          final rows = body['data'] as List<Map<String, dynamic>>;
          rows[1]['date'] = rows[0]['date'];
        }

        return jsonResponse(body);
      });

      await expectLater(
        service.fetchPeriod(startDate: '2026-11-02', endDate: '2026-11-08'),
        throwsA(isA<HistoryReportApiException>()),
      );
    });
  });

  group('Kesalahan koneksi dan respons', () {
    test('HTTP gagal menjadi error layanan', () async {
      final service = createService((request) async {
        return http.Response('Server error', 500);
      });

      await expectLater(
        service.fetchReadingPage(date: testDate),
        throwsA(
          isA<HistoryReportApiException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
    });

    test('JSON rusak menjadi error layanan', () async {
      final service = createService((request) async {
        return http.Response('bukan JSON', 200);
      });

      await expectLater(
        service.fetchReadingPage(date: testDate),
        throwsA(isA<HistoryReportApiException>()),
      );
    });

    test('Gangguan jaringan menjadi error layanan', () async {
      final service = createService((request) async {
        throw http.ClientException('Koneksi terputus');
      });

      await expectLater(
        service.fetchReadingPage(date: testDate),
        throwsA(
          isA<HistoryReportApiException>().having(
            (error) => error.message,
            'message',
            contains('Periksa koneksi internet'),
          ),
        ),
      );
    });
  });
}
