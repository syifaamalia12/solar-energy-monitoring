import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solar_energy_monitoring/services/prediction_service.dart';

Map<String, dynamic> predictionData() {
  return {
    'device_id': 'solar-001',
    'prediction_date': '2026-11-02',
    'predicted_energy_wh': 0.75,
    'model_name': 'Linear Regression',
    'created_at': '2026-10-31T18:57:10.231Z',
  };
}

http.Response successResponse(Map<String, dynamic> data) {
  return http.Response(
    jsonEncode({'status': 'success', 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

ApiPredictionService serviceFor(http.Client client) {
  return ApiPredictionService(
    baseUrl: 'https://example.com/',
    deviceId: 'solar-001',
    client: client,
  );
}

void main() {
  test('Mengambil prediksi perangkat tanpa token atau API key', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/ai/predictions/latest');
      expect(request.url.queryParameters, {'device_id': 'solar-001'});
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-api-key'), isFalse);

      return successResponse(predictionData());
    });
    addTearDown(client.close);

    final result = await serviceFor(client).fetchLatestPrediction();

    expect(result, isNotNull);
    expect(result!.deviceId, 'solar-001');
    expect(result.predictionDate, '2026-11-02');
    expect(result.predictedEnergyWh, 0.75);
    expect(result.modelName, 'Linear Regression');
    expect(result.createdAt, DateTime.utc(2026, 10, 31, 18, 57, 10, 231));
  });

  test('Nilai prediksi nol tetap menjadi data', () async {
    final client = MockClient((request) async {
      return successResponse({...predictionData(), 'predicted_energy_wh': 0});
    });
    addTearDown(client.close);

    final result = await serviceFor(client).fetchLatestPrediction();

    expect(result, isNotNull);
    expect(result!.predictedEnergyWh, 0);
  });

  test('Tanggal target lama tidak diganti menjadi besok', () async {
    final client = MockClient((request) async {
      return successResponse({
        ...predictionData(),
        'prediction_date': '2025-01-15',
      });
    });
    addTearDown(client.close);

    final result = await serviceFor(client).fetchLatestPrediction();

    expect(result!.predictionDate, '2025-01-15');
  });

  test('404 PREDICTION_NOT_FOUND menjadi data kosong', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'code': 'PREDICTION_NOT_FOUND',
          'detail': 'Belum ada hasil prediksi',
        }),
        404,
      );
    });
    addTearDown(client.close);

    expect(await serviceFor(client).fetchLatestPrediction(), isNull);
  });

  test('404 DEVICE_NOT_FOUND tetap menjadi error', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'code': 'DEVICE_NOT_FOUND',
          'detail': 'Perangkat tidak ditemukan',
        }),
        404,
      );
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(
        isA<PredictionApiException>().having(
          (error) => error.message,
          'message',
          contains('Perangkat tidak ditemukan'),
        ),
      ),
    );
  });

  test('404 umum tidak dianggap prediksi kosong', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(isA<PredictionApiException>()),
    );
  });

  test('503 tetap error meskipun membawa kode prediksi kosong', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'code': 'PREDICTION_NOT_FOUND'}), 503);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(
        isA<PredictionApiException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 503'),
        ),
      ),
    );
  });

  final invalidFields = <String, Object?>{
    'device_id': 'solar-002',
    'prediction_date': '2026-02-30',
    'predicted_energy_wh': -1,
    'model_name': '   ',
    'created_at': '2026-10-31T18:57:10',
  };

  for (final entry in invalidFields.entries) {
    test('Menolak data tidak sesuai pada ${entry.key}', () async {
      final client = MockClient((request) async {
        return successResponse({...predictionData(), entry.key: entry.value});
      });
      addTearDown(client.close);

      await expectLater(
        serviceFor(client).fetchLatestPrediction(),
        throwsA(isA<PredictionApiException>()),
      );
    });
  }

  test('Timestamp dengan offset dikonversi ke UTC secara benar', () async {
    final client = MockClient((request) async {
      return successResponse({
        ...predictionData(),
        'created_at': '2026-11-01T01:57:10.231+07:00',
      });
    });
    addTearDown(client.close);

    final result = await serviceFor(client).fetchLatestPrediction();

    expect(result!.createdAt, DateTime.utc(2026, 10, 31, 18, 57, 10, 231));
  });

  test('Menolak timestamp dengan jam tidak valid', () async {
    final client = MockClient((request) async {
      return successResponse({
        ...predictionData(),
        'created_at': '2026-10-31T25:57:10Z',
      });
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(isA<PredictionApiException>()),
    );
  });

  test('Respons sukses dengan data null tidak dianggap kosong', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'success', 'data': null}),
        200,
      );
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(isA<PredictionApiException>()),
    );
  });

  test('Menangani JSON rusak', () async {
    final client = MockClient((request) async {
      return http.Response('bukan JSON', 200);
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(isA<PredictionApiException>()),
    );
  });

  test('Menangani kegagalan koneksi', () async {
    final client = MockClient((request) async {
      throw http.ClientException('Simulasi koneksi gagal');
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(
        isA<PredictionApiException>().having(
          (error) => error.message,
          'message',
          contains('Periksa koneksi internet'),
        ),
      ),
    );
  });

  test('Menangani timeout', () async {
    final client = MockClient((request) async {
      throw TimeoutException('Simulasi timeout');
    });
    addTearDown(client.close);

    await expectLater(
      serviceFor(client).fetchLatestPrediction(),
      throwsA(
        isA<PredictionApiException>().having(
          (error) => error.message,
          'message',
          contains('Waktu permintaan habis'),
        ),
      ),
    );
  });
}
