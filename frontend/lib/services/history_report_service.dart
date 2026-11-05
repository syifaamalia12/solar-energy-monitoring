import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/history_report.dart';
import '../models/sensor_reading.dart';

abstract class HistoryReportService {
  Future<HistoryReport> fetchDay({required String date});

  Future<HistoryReport> fetchPeriod({
    required String startDate,
    required String endDate,
  });

  Future<HistoryReadingPage> fetchReadingPage({
    required String date,
    int offset = 0,
    String? snapshot,
  });
}

class HistoryReportApiException implements Exception {
  const HistoryReportApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiHistoryReportService implements HistoryReportService {
  ApiHistoryReportService({
    required this.baseUrl,
    required this.deviceId,
    this.client,
  });

  final String baseUrl;
  final String deviceId;

  // Client yang diberikan dari luar tetap dimiliki pemanggil.
  final http.Client? client;

  static const pageSize = 100;

  Future<Map<String, dynamic>> _get(
    String endpoint,
    Map<String, String> parameters,
  ) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/monitoring/$endpoint')
        .replace(queryParameters: {'device_id': deviceId, ...parameters});

    try {
      final headers = {'Accept': 'application/json'};

      final response =
          await (client == null
                  ? http.get(uri, headers: headers)
                  : client!.get(uri, headers: headers))
              .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw HistoryReportApiException(
          'Gagal mengambil riwayat (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic> ||
          decoded['device_id'] != deviceId) {
        throw const FormatException('Respons perangkat tidak sesuai');
      }

      if (endpoint != 'history' && decoded['timezone'] != 'Asia/Jakarta') {
        throw const FormatException('Zona waktu tidak sesuai');
      }

      return decoded;
    } on TimeoutException {
      throw const HistoryReportApiException(
        'Waktu permintaan habis. Silakan coba lagi.',
      );
    } on http.ClientException {
      throw const HistoryReportApiException(
        'Tidak dapat terhubung ke server. Periksa koneksi internet.',
      );
    } on FormatException {
      throw const HistoryReportApiException(
        'Format data riwayat dari server tidak sesuai.',
      );
    }
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Objek riwayat tidak valid');
    }

    return value;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> json) {
    final rows = json['data'];
    final count = json['count'];

    if (rows is! List || count is! int || count < 0 || count != rows.length) {
      throw const FormatException('Daftar riwayat tidak valid');
    }

    return rows.map(_object).toList();
  }

  String _dateOfReading(SensorReading reading) {
    return reading.timestamp
        .toUtc()
        .add(const Duration(hours: 7))
        .toIso8601String()
        .substring(0, 10);
  }

  @override
  Future<HistoryReadingPage> fetchReadingPage({
    required String date,
    int offset = 0,
    String? snapshot,
  }) async {
    validateHistoryDate(date);

    if (offset < 0 || offset > 1000000) {
      throw ArgumentError.value(offset, 'offset');
    }

    if (offset > 0 && (snapshot == null || snapshot.isEmpty)) {
      throw ArgumentError(
        'Halaman berikutnya wajib memakai snapshot halaman pertama.',
      );
    }

    try {
      final json = await _get('history', {
        'date': date,
        'limit': '$pageSize',
        'offset': '$offset',
        'snapshot': ?snapshot,
      });

      if (json['date'] != date ||
          json['limit'] != pageSize ||
          json['offset'] != offset) {
        throw const FormatException('Metadata halaman tidak sesuai');
      }

      final token = json['snapshot'];
      final hasMore = json['has_more'];
      final nextOffset = json['next_offset'];
      final items = _items(json);

      if (token is! String ||
          token.isEmpty ||
          hasMore is! bool ||
          items.length > pageSize ||
          (snapshot != null && token != snapshot)) {
        throw const FormatException('Pagination tidak valid');
      }

      if (hasMore) {
        if (nextOffset is! int ||
            nextOffset != offset + pageSize ||
            nextOffset > 1000000 ||
            items.length != pageSize) {
          throw const FormatException('Offset berikutnya tidak valid');
        }
      } else if (nextOffset != null) {
        throw const FormatException('Halaman akhir tidak valid');
      }

      final readings = items.map(SensorReading.fromJson).toList();
      final ids = <String>{};

      for (var index = 0; index < readings.length; index++) {
        final reading = readings[index];

        if (reading.deviceId != deviceId ||
            _dateOfReading(reading) != date ||
            !ids.add(reading.readingId)) {
          throw const FormatException('Pembacaan tidak sesuai');
        }

        if (index > 0 &&
            readings[index - 1].timestamp.isBefore(reading.timestamp)) {
          throw const FormatException('Urutan pembacaan tidak sesuai');
        }
      }

      return HistoryReadingPage(
        date: date,
        readings: List<SensorReading>.unmodifiable(readings),
        offset: offset,
        nextOffset: hasMore ? nextOffset as int : null,
        snapshot: token,
      );
    } on FormatException {
      throw const HistoryReportApiException(
        'Format data riwayat dari server tidak sesuai.',
      );
    }
  }

  @override
  Future<HistoryReport> fetchDay({required String date}) async {
    validateHistoryDate(date);

    try {
      // Rekap tidak dihitung dari halaman tabel yang belum lengkap.
      final results = await Future.wait<Object>([
        _get('daily-summary', {'date': date}),
        _get('hourly-summary', {'date': date}),
        fetchReadingPage(date: date),
      ]);

      final daily = results[0] as Map<String, dynamic>;
      final hourly = results[1] as Map<String, dynamic>;
      final page = results[2] as HistoryReadingPage;
      final summaryJson = _object(daily['data']);

      if (summaryJson['date'] != date || hourly['date'] != date) {
        throw const FormatException('Tanggal rekap tidak sesuai');
      }

      final buckets = _items(hourly)
          .map((item) => HistoryBucket.hourly(item, date: date))
          .toList();

      if (buckets.length != 24) {
        throw const FormatException('Rekap jam tidak lengkap');
      }

      for (var hour = 0; hour < 24; hour++) {
        if (buckets[hour].hour != hour) {
          throw const FormatException('Urutan jam tidak sesuai');
        }
      }

      return HistoryReport(
        startDate: date,
        endDate: date,
        summary: HistorySummary.fromJson(summaryJson),
        buckets: List<HistoryBucket>.unmodifiable(buckets),
        firstPage: page,
      );
    } on FormatException {
      throw const HistoryReportApiException(
        'Format data riwayat dari server tidak sesuai.',
      );
    }
  }

  @override
  Future<HistoryReport> fetchPeriod({
    required String startDate,
    required String endDate,
  }) async {
    validateHistoryDate(startDate);
    validateHistoryDate(endDate);

    final start = DateTime.parse('${startDate}T00:00:00Z');
    final end = DateTime.parse('${endDate}T00:00:00Z');
    final days = end.difference(start).inDays + 1;

    if (days < 1 || days > 366) {
      throw ArgumentError('Rentang harus berisi 1–366 hari.');
    }

    try {
      final parameters = {'start_date': startDate, 'end_date': endDate};

      final results = await Future.wait<Map<String, dynamic>>([
        _get('daily-history', parameters),
        _get('period-summary', parameters),
      ]);

      final daily = results[0];
      final period = results[1];

      for (final json in results) {
        if (json['start_date'] != startDate || json['end_date'] != endDate) {
          throw const FormatException('Rentang rekap tidak sesuai');
        }
      }

      final buckets = _items(daily).map(HistoryBucket.daily).toList();

      if (buckets.length != days) {
        throw const FormatException('Rekap tanggal tidak lengkap');
      }

      for (var index = 0; index < days; index++) {
        final expectedDate = start
            .add(Duration(days: index))
            .toIso8601String()
            .substring(0, 10);

        if (buckets[index].date != expectedDate) {
          throw const FormatException('Urutan tanggal tidak sesuai');
        }
      }

      return HistoryReport(
        startDate: startDate,
        endDate: endDate,
        summary: HistorySummary.fromJson(_object(period['data'])),
        buckets: List<HistoryBucket>.unmodifiable(buckets),
      );
    } on FormatException {
      throw const HistoryReportApiException(
        'Format data riwayat dari server tidak sesuai.',
      );
    }
  }
}
