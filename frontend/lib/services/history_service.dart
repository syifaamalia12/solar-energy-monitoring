import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/daily_energy.dart';

abstract class HistoryService {
  Future<List<DailyEnergy>> fetchHistory({required int days});
}

class HistoryApiException implements Exception {
  const HistoryApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiHistoryService implements HistoryService {
  ApiHistoryService({
    required this.baseUrl,
    required this.deviceId,
    this.client,
  });

  final String baseUrl;
  final String deviceId;

  // Client yang diberikan untuk tes ditutup oleh pemiliknya.
  final http.Client? client;

  @override
  Future<List<DailyEnergy>> fetchHistory({required int days}) async {
    if (!const [7, 14, 30].contains(days)) {
      throw ArgumentError.value(days, 'days', 'Gunakan 7, 14, atau 30');
    }

    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/monitoring/daily-history').replace(
      queryParameters: {'device_id': deviceId, 'days': days.toString()},
    );

    try {
      final headers = {'Accept': 'application/json'};

      final response =
          await (client == null
                  ? http.get(uri, headers: headers)
                  : client!.get(uri, headers: headers))
              .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw HistoryApiException(
          'Gagal mengambil riwayat (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic> ||
          decoded['device_id'] != deviceId ||
          decoded['timezone'] != 'Asia/Jakarta') {
        throw const FormatException('Respons tidak sesuai');
      }

      final rows = decoded['data'];
      final count = decoded['count'];

      if (rows is! List || count is! int || count < 0 || count != rows.length) {
        throw const FormatException('Daftar riwayat tidak valid');
      }

      final result = <DailyEnergy>[];
      final dates = <String>{};

      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Item riwayat tidak valid');
        }

        final item = DailyEnergy.fromJson(row);

        if (!dates.add(item.date)) {
          throw const FormatException('Tanggal riwayat duplikat');
        }

        // Tanpa pembacaan bukan berarti produksi energi nol.
        // Energi 0 tetap disimpan jika readingCount > 0.
        if (item.readingCount > 0) {
          result.add(item);
        }
      }

      // Format YYYY-MM-DD dapat diurutkan secara alfabetis.
      result.sort((a, b) => a.date.compareTo(b.date));

      // Tidak menambahkan tanggal atau nilai nol buatan.
      return List<DailyEnergy>.unmodifiable(result);
    } on TimeoutException {
      throw const HistoryApiException(
        'Waktu permintaan habis. Silakan coba lagi.',
      );
    } on http.ClientException {
      throw const HistoryApiException(
        'Tidak dapat terhubung ke server. Periksa koneksi internet.',
      );
    } on FormatException {
      throw const HistoryApiException(
        'Format data riwayat dari server tidak sesuai.',
      );
    }
  }
}
