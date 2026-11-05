class SensorReading {
  const SensorReading({
    required this.readingId,
    required this.deviceId,
    required this.timestamp,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.energyWh,
    required this.intervalSeconds,
  });

  final String readingId;
  final String deviceId;
  final DateTime timestamp;
  final double voltageV;
  final double currentA;
  final double powerW;

  // Energi satu interval pengukuran, bukan total energi harian.
  final double energyWh;

  final int intervalSeconds;

  static double _number(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        !value.toDouble().isFinite) {
      throw const FormatException('Nilai pengukuran tidak valid');
    }

    return value.toDouble();
  }

  static DateTime _timestamp(Object? value) {
    if (value is! String) {
      throw const FormatException('Timestamp tidak valid');
    }

    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T'
      r'(\d{2}):(\d{2}):(\d{2})'
      r'(?:\.\d+)?'
      r'(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(value);

    if (match == null) {
      throw const FormatException('Timestamp wajib memiliki timezone');
    }

    final date = match.group(1)!;
    final parsedDate = DateTime.tryParse('${date}T00:00:00Z');

    if (date.startsWith('0000') ||
        parsedDate == null ||
        parsedDate.toIso8601String().substring(0, 10) != date ||
        int.parse(match.group(2)!) > 23 ||
        int.parse(match.group(3)!) > 59 ||
        int.parse(match.group(4)!) > 59) {
      throw const FormatException('Tanggal atau waktu tidak valid');
    }

    final zone = match.group(5)!;

    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4, 6)) > 59)) {
      throw const FormatException('Timezone tidak valid');
    }

    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      throw const FormatException('Timestamp tidak valid');
    }

    return parsed.toUtc();
  }

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    final readingId = json['reading_id'];
    final deviceId = json['device_id'];
    final interval = json['interval_seconds'];

    if (readingId is! String || readingId.trim().isEmpty) {
      throw const FormatException('ID pembacaan tidak valid');
    }

    if (deviceId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(deviceId)) {
      throw const FormatException('ID perangkat tidak valid');
    }

    if (interval is! int || interval < 1 || interval > 3600) {
      throw const FormatException('Interval pengukuran tidak valid');
    }

    return SensorReading(
      readingId: readingId,
      deviceId: deviceId,
      timestamp: _timestamp(json['timestamp']),
      voltageV: _number(json['voltage_v']),
      currentA: _number(json['current_a']),
      powerW: _number(json['power_w']),
      energyWh: _number(json['energy_wh']),
      intervalSeconds: interval,
    );
  }
}
