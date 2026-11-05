import 'sensor_reading.dart';

String validateHistoryDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Tanggal riwayat tidak valid');
  }

  final parsed = DateTime.tryParse('${value}T00:00:00Z');

  if (parsed == null ||
      parsed.year < 1 ||
      parsed.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Tanggal riwayat tidak valid');
  }

  return value;
}

double historyNumber(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      !value.toDouble().isFinite) {
    throw const FormatException('Angka riwayat tidak valid');
  }

  return value.toDouble();
}

int historyCount(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Jumlah pembacaan tidak valid');
  }

  return value;
}

class HistorySummary {
  const HistorySummary({
    required this.totalEnergyWh,
    required this.readingCount,
    required this.averageVoltageV,
    required this.averageCurrentA,
    required this.averagePowerW,
  });

  final double totalEnergyWh;
  final int readingCount;
  final double averageVoltageV;
  final double averageCurrentA;
  final double averagePowerW;

  bool get hasReadings => readingCount > 0;

  factory HistorySummary.fromJson(Map<String, dynamic> json) {
    return HistorySummary(
      totalEnergyWh: historyNumber(json['total_energy_wh']),
      readingCount: historyCount(json['reading_count']),
      averageVoltageV: historyNumber(json['avg_voltage_v']),
      averageCurrentA: historyNumber(json['avg_current_a']),
      averagePowerW: historyNumber(json['avg_power_w']),
    );
  }
}

class HistoryBucket {
  const HistoryBucket({
    required this.date,
    required this.totalEnergyWh,
    required this.readingCount,
    this.hour,
  });

  final String date;
  final int? hour;
  final double totalEnergyWh;
  final int readingCount;

  bool get hasReadings => readingCount > 0;

  factory HistoryBucket.daily(Map<String, dynamic> json) {
    return HistoryBucket(
      date: validateHistoryDate(json['date']),
      totalEnergyWh: historyNumber(json['total_energy_wh']),
      readingCount: historyCount(json['reading_count']),
    );
  }

  factory HistoryBucket.hourly(
    Map<String, dynamic> json, {
    required String date,
  }) {
    final hour = json['hour'];

    if (hour is! int || hour < 0 || hour > 23) {
      throw const FormatException('Jam riwayat tidak valid');
    }

    return HistoryBucket(
      date: validateHistoryDate(date),
      hour: hour,
      totalEnergyWh: historyNumber(json['total_energy_wh']),
      readingCount: historyCount(json['reading_count']),
    );
  }
}

class HistoryReadingPage {
  const HistoryReadingPage({
    required this.date,
    required this.readings,
    required this.offset,
    required this.nextOffset,
    required this.snapshot,
  });

  final String date;

  // Urutan terbaru ke terlama, mengikuti API.
  final List<SensorReading> readings;

  final int offset;
  final int? nextOffset;

  // Token batas pembacaan, bukan token autentikasi.
  final String snapshot;

  bool get hasMore => nextOffset != null;
}

class HistoryReport {
  const HistoryReport({
    required this.startDate,
    required this.endDate,
    required this.summary,
    required this.buckets,
    this.firstPage,
  });

  final String startDate;
  final String endDate;
  final HistorySummary summary;

  // Harian: 24 jam. Mingguan/Bulanan: satu item per tanggal.
  // Item tanpa data tetap disimpan, dibedakan melalui readingCount.
  final List<HistoryBucket> buckets;

  // Tabel pembacaan sensor hanya untuk mode Harian.
  final HistoryReadingPage? firstPage;
}
