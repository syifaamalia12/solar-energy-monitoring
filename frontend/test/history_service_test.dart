import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solar_energy_monitoring/services/history_service.dart';

Map<String, Object> reading(String date, num energy, {int count = 1}) {
  return {'date': date, 'total_energy_wh': energy, 'reading_count': count};
}

http.Response responseFor(
  List<Map<String, Object>> rows, {
  String deviceId = 'solar-001',
  String timezone = 'Asia/Jakarta',
}) {
  return http.Response(
    jsonEncode({
      'device_id': deviceId,
      'timezone': timezone,
      'count': rows.length,
      'data': rows,
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

ApiHistoryService serviceFor(http.Client client) {
  return ApiHistoryService(
    baseUrl: 'https://example.com/',
    deviceId: 'solar-001',
    client: client,
  );
}

void main() {
  for (final days in [7, 14, 30]) {
    test('Mengirim perangkat dan periode $days hari tanpa token', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/monitoring/daily-history');
        expect(request.url.queryParameters, {
          'device_id': 'solar-001',
          'days': '$days',
        });
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('x-api-key'), isFalse);

        return responseFor([]);
      });
      addTearDown(client.close);

      expect(await serviceFor(client).fetchHistory(days: days), isEmpty);
    });
  }

  test(
    'Mengurutkan tanggal dan mempertahankan energi kecil serta nol',
    () async {
      final client = MockClient((request) async {
        return responseFor([
          reading('2026-11-02', 0),
          reading('2026-10-29', 0.00001952, count: 8),
        ]);
      });
      addTearDown(client.close);

      final data = await serviceFor(client).fetchHistory(days: 7);

      expect(data.map((item) => item.date).toList(), [
        '2026-10-29',
        '2026-11-02',
      ]);
      expect(data.first.totalEnergyWh, closeTo(0.00001952, 1e-12));
      expect(data.last.totalEnergyWh, 0);

      // Hari di antaranya tidak ditambahkan sebagai energi nol.
      expect(data, hasLength(2));
    },
  );

  test('Satu tanggal tetap menghasilkan satu data', () async {
    final client = MockClient((request) async {
      return responseFor([reading('2026-11-01', 0.75)]);
    });
    addTearDown(client.close);

    final data = await serviceFor(client).fetchHistory(days: 14);

    expect(data, hasLength(1));
    expect(data.single.totalEnergyWh, 0.75);
  });

  test('Hari tanpa pembacaan tidak dianggap sebagai energi nol', () async {
    final client = MockClient((request) async {
      return responseFor([reading('2026-11-01', 0, count: 0)]);
    });
    addTearDown(client.close);

    expect(await serviceFor(client).fetchHistory(days: 7), isEmpty);
  });

  test('Menolak perangkat yang tidak sesuai', () async {
    final client = MockClient((request) async {
      return responseFor([], deviceId: 'solar-002');
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(isA<HistoryApiException>()),
    );
  });

  test('Menolak zona waktu yang tidak sesuai', () async {
    final client = MockClient((request) async {
      return responseFor([], timezone: 'UTC');
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(isA<HistoryApiException>()),
    );
  });

  test('Menolak tanggal kalender yang tidak valid', () async {
    final client = MockClient((request) async {
      return responseFor([reading('2026-02-30', 1)]);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(isA<HistoryApiException>()),
    );
  });

  test('Menolak energi negatif', () async {
    final client = MockClient((request) async {
      return responseFor([reading('2026-11-01', -1)]);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(isA<HistoryApiException>()),
    );
  });

  test('Menolak tanggal duplikat', () async {
    final client = MockClient((request) async {
      return responseFor([reading('2026-11-01', 1), reading('2026-11-01', 2)]);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(isA<HistoryApiException>()),
    );
  });

  test('Menangani kegagalan HTTP', () async {
    final client = MockClient((request) async {
      return http.Response('Server error', 500);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(
        isA<HistoryApiException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 500'),
        ),
      ),
    );
  });

  test('Menangani kegagalan koneksi', () async {
    final client = MockClient((request) async {
      throw http.ClientException('Simulasi koneksi gagal');
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(
        isA<HistoryApiException>().having(
          (error) => error.message,
          'message',
          contains('Periksa koneksi internet'),
        ),
      ),
    );
  });

  test('Menangani JSON rusak', () async {
    final client = MockClient((request) async {
      return http.Response('bukan JSON', 200);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 7),
      throwsA(isA<HistoryApiException>()),
    );
  });

  test('Menolak periode selain 7, 14, dan 30 sebelum request', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return responseFor([]);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchHistory(days: 10),
      throwsArgumentError,
    );
    expect(requests, 0);
  });
}
