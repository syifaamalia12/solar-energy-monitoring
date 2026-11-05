import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solar_energy_monitoring/models/sensor_reading.dart';
import 'package:solar_energy_monitoring/services/monitoring_service.dart';

Map<String, dynamic> sampleReading({
  String id = 'reading-1',
  String deviceId = 'solar-001',
  String timestamp = '2026-11-02T10:00:22Z',
  double voltage = 4.324,
  double current = 0.0011,
  double power = 0.0047564,
  double energy = 0.00007927333333333335,
}) {
  return {
    'reading_id': id,
    'device_id': deviceId,
    'timestamp': timestamp,
    'voltage_v': voltage,
    'current_a': current,
    'power_w': power,
    'energy_wh': energy,
    'interval_seconds': 60,
  };
}

http.Response successResponse(List<Map<String, dynamic>> rows) {
  return http.Response(
    jsonEncode({'device_id': 'solar-001', 'count': rows.length, 'data': rows}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

ApiMonitoringService buildService(MockClient client) {
  addTearDown(client.close);

  return ApiMonitoringService(
    baseUrl: 'https://example.test/',
    deviceId: 'solar-001',
    client: client,
  );
}

void main() {
  test('Mengirim query yang benar tanpa API key', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/monitoring/history');
      expect(request.url.queryParameters['device_id'], 'solar-001');
      expect(request.url.queryParameters['limit'], '5');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers.containsKey('x-api-key'), isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);

      return successResponse([sampleReading()]);
    });

    final service = buildService(client);
    final rows = await service.fetchReadings(limit: 5);

    expect(rows, hasLength(1));
    expect(rows.single.voltageV, 4.324);
    expect(rows.single.currentA, 0.0011);
    expect(rows.single.powerW, 0.0047564);
    expect(rows.single.energyWh, closeTo(0.00007927333333333335, 1e-12));
    expect(rows.single.intervalSeconds, 60);
  });

  test('Mengurutkan pembacaan dari waktu paling awal', () async {
    final client = MockClient((request) async {
      return successResponse([
        sampleReading(id: 'new'),
        sampleReading(id: 'old', timestamp: '2026-11-02T09:59:22Z'),
      ]);
    });

    final service = buildService(client);
    final rows = await service.fetchReadings();

    expect(rows.map((row) => row.readingId).toList(), ['old', 'new']);
  });

  test('Data kosong tidak diganti pembacaan buatan', () async {
    final client = MockClient((request) async {
      return successResponse([]);
    });

    final service = buildService(client);

    expect(await service.fetchReadings(), isEmpty);
  });

  test('Nilai nol tetap dianggap pembacaan valid', () {
    final reading = SensorReading.fromJson(
      sampleReading(voltage: 0, current: 0, power: 0, energy: 0),
    );

    expect(reading.voltageV, 0);
    expect(reading.currentA, 0);
    expect(reading.powerW, 0);
    expect(reading.energyWh, 0);
  });

  test('Timestamp dengan offset dikonversi ke UTC', () {
    final reading = SensorReading.fromJson(
      sampleReading(timestamp: '2026-11-02T17:00:22+07:00'),
    );

    expect(reading.timestamp, DateTime.utc(2026, 11, 2, 10, 0, 22));
  });

  test('Timestamp tanpa timezone ditolak', () {
    expect(
      () => SensorReading.fromJson(
        sampleReading(timestamp: '2026-11-02T17:00:22'),
      ),
      throwsFormatException,
    );
  });

  test('Pembacaan milik perangkat lain ditolak', () async {
    final client = MockClient((request) async {
      return successResponse([sampleReading(deviceId: 'solar-002')]);
    });

    final service = buildService(client);

    await expectLater(
      service.fetchReadings(),
      throwsA(isA<MonitoringApiException>()),
    );
  });

  test('Jumlah data yang tidak sesuai ditolak', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'device_id': 'solar-001',
          'count': 2,
          'data': [sampleReading()],
        }),
        200,
      );
    });

    final service = buildService(client);

    await expectLater(
      service.fetchReadings(),
      throwsA(isA<MonitoringApiException>()),
    );
  });

  test('Kegagalan jaringan menghasilkan pesan koneksi', () async {
    final client = MockClient((request) async {
      throw http.ClientException('Simulasi koneksi gagal');
    });

    final service = buildService(client);

    await expectLater(
      service.fetchReadings(),
      throwsA(
        isA<MonitoringApiException>().having(
          (error) => error.message,
          'message',
          'Tidak dapat terhubung ke server. Periksa koneksi internet.',
        ),
      ),
    );
  });

  test('HTTP error tidak dianggap sebagai data kosong', () async {
    final client = MockClient((request) async {
      return http.Response('Server error', 503);
    });

    final service = buildService(client);

    await expectLater(
      service.fetchReadings(),
      throwsA(
        isA<MonitoringApiException>().having(
          (error) => error.message,
          'message',
          'Gagal mengambil monitoring (HTTP 503).',
        ),
      ),
    );
  });
}
