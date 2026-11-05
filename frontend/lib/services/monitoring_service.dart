import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/sensor_reading.dart';

abstract class MonitoringService {
  Future<List<SensorReading>> fetchReadings({int limit = 100});
}

class MonitoringApiException implements Exception {
  const MonitoringApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiMonitoringService implements MonitoringService {
  ApiMonitoringService({
    required this.baseUrl,
    required this.deviceId,
    this.client,
  });

  final String baseUrl;
  final String deviceId;

  // Client yang diberikan untuk tes ditutup oleh pemiliknya.
  final http.Client? client;

  @override
  Future<List<SensorReading>> fetchReadings({int limit = 100}) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'Gunakan nilai 1 sampai 1000');
    }

    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/monitoring/history').replace(
      queryParameters: {'device_id': deviceId, 'limit': limit.toString()},
    );

    try {
      final headers = {'Accept': 'application/json'};

      final response =
          await (client == null
                  ? http.get(uri, headers: headers)
                  : client!.get(uri, headers: headers))
              .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw MonitoringApiException(
          'Gagal mengambil monitoring (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic> ||
          decoded['device_id'] != deviceId) {
        throw const FormatException('Respons perangkat tidak sesuai');
      }

      final rows = decoded['data'];
      final count = decoded['count'];

      if (rows is! List || count is! int || count < 0 || count != rows.length) {
        throw const FormatException('Daftar pembacaan tidak valid');
      }

      final readings = <SensorReading>[];

      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Item pembacaan tidak valid');
        }

        final reading = SensorReading.fromJson(row);

        if (reading.deviceId != deviceId) {
          throw const FormatException('Perangkat pembacaan tidak sesuai');
        }

        readings.add(reading);
      }

      // API mengirim terbaru dahulu.
      // Urutan waktu menaik lebih sesuai untuk sumbu grafik.
      readings.sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);

        if (byTime != 0) return byTime;

        return a.readingId.compareTo(b.readingId);
      });

      // Tidak menambahkan pembacaan atau nilai nol buatan.
      return List<SensorReading>.unmodifiable(readings);
    } on TimeoutException {
      throw const MonitoringApiException(
        'Waktu permintaan habis. Silakan coba lagi.',
      );
    } on http.ClientException {
      throw const MonitoringApiException(
        'Tidak dapat terhubung ke server. Periksa koneksi internet.',
      );
    } on FormatException {
      throw const MonitoringApiException(
        'Format data monitoring dari server tidak sesuai.',
      );
    }
  }
}
