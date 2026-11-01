import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dashboard_data.dart';
import 'dashboard_service.dart';

class DashboardApiException implements Exception {
  const DashboardApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiDashboardService implements DashboardService {
  ApiDashboardService({
    required this.baseUrl,
    required this.deviceId,
    this.client,
  });

  final String baseUrl;
  final String deviceId;

  // Jika diberikan untuk tes, client ditutup oleh pemiliknya.
  final http.Client? client;

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path').replace(queryParameters: query);

    try {
      final headers = {'Accept': 'application/json'};

      final response =
          await (client == null
                  ? http.get(uri, headers: headers)
                  : client!.get(uri, headers: headers))
              .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw DashboardApiException(
          'Gagal mengambil data (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return _object(decoded);
    } on TimeoutException {
      throw const DashboardApiException(
        'Waktu permintaan habis. Silakan coba lagi.',
      );
    } on http.ClientException {
      throw const DashboardApiException(
        'Tidak dapat terhubung ke server. Periksa koneksi internet.',
      );
    } on FormatException {
      throw const DashboardApiException(
        'Format data dari server tidak sesuai.',
      );
    }
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }

    return value;
  }

  double _number(Object? value) {
    if (value is! num || !value.isFinite || value < 0) {
      throw const FormatException('Invalid numeric value');
    }

    return value.toDouble();
  }

  String _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid date');
    }

    final parsed = DateTime.tryParse('${value}T00:00:00Z');

    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('Invalid date');
    }

    return value;
  }

  @override
  Future<DashboardData?> fetchDashboard() async {
    try {
      final results = await Future.wait([
        _get('/api/v1/monitoring/latest', {'device_id': deviceId}),
        _get('/api/v1/monitoring/daily-summary', {'device_id': deviceId}),
      ]);

      final latest = results[0];
      final summary = results[1];

      if (latest['device_id'] != deviceId ||
          summary['device_id'] != deviceId ||
          summary['timezone'] != 'Asia/Jakarta') {
        throw const FormatException('Device or timezone mismatch');
      }

      if (!latest.containsKey('data')) {
        throw const FormatException('Missing latest data');
      }

      final daily = _object(summary['data']);
      final date = _date(daily['date']);
      final count = daily['reading_count'];
      final total = _number(daily['total_energy_wh']);

      if (count is! int || count < 0) {
        throw const FormatException('Invalid reading count');
      }

      // Latest kosong bukan kegagalan jaringan.
      if (latest['data'] == null) return null;

      final reading = _object(latest['data']);
      final timestamp = reading['timestamp'];

      if (reading['device_id'] != deviceId ||
          timestamp is! String ||
          !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp)) {
        throw const FormatException('Invalid reading');
      }

      final parsedTimestamp = DateTime.tryParse(timestamp);

      if (parsedTimestamp == null) {
        throw const FormatException('Invalid timestamp');
      }

      return DashboardData(
        deviceId: deviceId,
        voltageV: _number(reading['voltage_v']),
        currentA: _number(reading['current_a']),
        powerW: _number(reading['power_w']),
        totalEnergyWh: total,
        summaryDate: date,
        readingTimestamp: parsedTimestamp,
        readingCount: count,

        // Berasal dari API; bukan berarti asal sensor sudah diverifikasi.
        isTestData: false,
      );
    } on FormatException {
      throw const DashboardApiException(
        'Format data dari server tidak sesuai.',
      );
    }
  }
}
