import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/energy_prediction.dart';

abstract class PredictionService {
  Future<EnergyPrediction?> fetchLatestPrediction();
}

class PredictionApiException implements Exception {
  const PredictionApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiPredictionService implements PredictionService {
  ApiPredictionService({
    required this.baseUrl,
    required this.deviceId,
    this.client,
  });

  final String baseUrl;
  final String deviceId;

  // Client yang diberikan untuk tes ditutup oleh pemiliknya.
  final http.Client? client;

  @override
  Future<EnergyPrediction?> fetchLatestPrediction() async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/ai/predictions/latest')
        .replace(queryParameters: {'device_id': deviceId});

    try {
      final headers = {'Accept': 'application/json'};

      final response =
          await (client == null
                  ? http.get(uri, headers: headers)
                  : client!.get(uri, headers: headers))
              .timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) {
        final error = _object(jsonDecode(utf8.decode(response.bodyBytes)));

        if (error['code'] == 'PREDICTION_NOT_FOUND') {
          return null;
        }

        if (error['code'] == 'DEVICE_NOT_FOUND') {
          throw const PredictionApiException(
            'Perangkat tidak ditemukan atau belum diizinkan '
            'untuk akses publik.',
          );
        }

        throw const PredictionApiException(
          'Endpoint atau data perangkat tidak ditemukan (HTTP 404).',
        );
      }

      if (response.statusCode != 200) {
        throw PredictionApiException(
          'Gagal mengambil prediksi (HTTP ${response.statusCode}).',
        );
      }

      final decoded = _object(jsonDecode(utf8.decode(response.bodyBytes)));

      if (decoded['status'] != 'success') {
        throw const FormatException('Status respons tidak sesuai');
      }

      // Respons sukses wajib membawa objek prediksi.
      // Data kosong mengikuti kontrak HTTP 404 PREDICTION_NOT_FOUND.
      final prediction = EnergyPrediction.fromJson(_object(decoded['data']));

      if (prediction.deviceId != deviceId) {
        throw const FormatException('Perangkat tidak sesuai');
      }

      return prediction;
    } on TimeoutException {
      throw const PredictionApiException(
        'Waktu permintaan habis. Silakan coba lagi.',
      );
    } on http.ClientException {
      throw const PredictionApiException(
        'Tidak dapat terhubung ke server. Periksa koneksi internet.',
      );
    } on FormatException {
      throw const PredictionApiException(
        'Format data prediksi dari server tidak sesuai.',
      );
    }
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Objek JSON tidak valid');
    }

    return value;
  }
}
