import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solar_energy_monitoring/services/api_dashboard_service.dart';

Map<String, dynamic> latestResponse() {
  return {
    'device_id': 'solar-001',
    'data': {
      'device_id': 'solar-001',
      'voltage_v': 1.952,
      'current_a': 0.0002,
      'power_w': 0.0003904,
      'timestamp': '2026-10-29T15:28:05Z',
    },
  };
}

Map<String, dynamic> summaryResponse({int count = 0}) {
  return {
    'device_id': 'solar-001',
    'timezone': 'Asia/Jakarta',
    'data': {
      'date': '2026-11-01',
      'total_energy_wh': count == 0 ? 0 : 0.00001952,
      'reading_count': count,
    },
  };
}

ApiDashboardService createService(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = MockClient(handler);
  addTearDown(client.close);

  return ApiDashboardService(
    baseUrl: 'https://example.test',
    deviceId: 'solar-001',
    client: client,
  );
}

void main() {
  test('Mengambil latest dan rekap tanpa token atau API key', () async {
    final paths = <String>[];

    final service = createService((request) async {
      paths.add(request.url.path);

      expect(request.method, 'GET');
      expect(request.url.queryParameters['device_id'], 'solar-001');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-api-key'), isFalse);

      final body = request.url.path.endsWith('/latest')
          ? latestResponse()
          : summaryResponse(count: 8);

      return http.Response(jsonEncode(body), 200);
    });

    final data = await service.fetchDashboard();

    expect(
      paths,
      containsAll([
        '/api/v1/monitoring/latest',
        '/api/v1/monitoring/daily-summary',
      ]),
    );
    expect(paths.length, 2);
    expect(data, isNotNull);
    expect(data!.voltageV, 1.952);
    expect(data.currentA, 0.0002);
    expect(data.powerW, 0.0003904);
    expect(data.totalEnergyWh, 0.00001952);
    expect(data.readingCount, 8);
    expect(data.hasDailyReadings, isTrue);
    expect(data.isTestData, isFalse);
    expect(
      data.readingTimestamp.toUtc(),
      DateTime.utc(2026, 10, 29, 15, 28, 5),
    );
  });

  test('Rekap tanpa pembacaan ditandai belum tersedia', () async {
    final service = createService((request) async {
      final body = request.url.path.endsWith('/latest')
          ? latestResponse()
          : summaryResponse();

      return http.Response(jsonEncode(body), 200);
    });

    final data = await service.fetchDashboard();

    expect(data, isNotNull);
    expect(data!.readingCount, 0);
    expect(data.hasDailyReadings, isFalse);
  });

  test('Latest null menghasilkan kondisi kosong', () async {
    final service = createService((request) async {
      final body = request.url.path.endsWith('/latest')
          ? {'device_id': 'solar-001', 'data': null}
          : summaryResponse();

      return http.Response(jsonEncode(body), 200);
    });

    expect(await service.fetchDashboard(), isNull);
  });

  test('HTTP gagal menghasilkan error, bukan data kosong', () async {
    final service = createService((request) async {
      return http.Response('{"detail":"Unavailable"}', 503);
    });

    await expectLater(
      service.fetchDashboard(),
      throwsA(isA<DashboardApiException>()),
    );
  });

  test('JSON rusak menghasilkan error', () async {
    final service = createService((request) async {
      return http.Response('bukan JSON', 200);
    });

    await expectLater(
      service.fetchDashboard(),
      throwsA(isA<DashboardApiException>()),
    );
  });

  test('Data perangkat lain ditolak', () async {
    final service = createService((request) async {
      final body = request.url.path.endsWith('/latest')
          ? latestResponse()
          : summaryResponse();

      body['device_id'] = 'solar-lain';

      return http.Response(jsonEncode(body), 200);
    });

    await expectLater(
      service.fetchDashboard(),
      throwsA(isA<DashboardApiException>()),
    );
  });

  test('Nilai sensor tidak valid ditolak', () async {
    final service = createService((request) async {
      final body = request.url.path.endsWith('/latest')
          ? latestResponse()
          : summaryResponse();

      if (request.url.path.endsWith('/latest')) {
        final reading = body['data'] as Map<String, dynamic>;
        reading['voltage_v'] = -1;
      }

      return http.Response(jsonEncode(body), 200);
    });

    await expectLater(
      service.fetchDashboard(),
      throwsA(isA<DashboardApiException>()),
    );
  });
}
