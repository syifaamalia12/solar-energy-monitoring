class EnergyPrediction {
  const EnergyPrediction({
    required this.deviceId,
    required this.predictionDate,
    required this.predictedEnergyWh,
    required this.modelName,
    required this.createdAt,
  });

  final String deviceId;

  // Tanggal target mengikuti backend, bukan otomatis besok.
  final String predictionDate;

  final double predictedEnergyWh;
  final String modelName;
  final DateTime createdAt;

  static bool _validDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        value.startsWith('0000')) {
      return false;
    }

    final parsed = DateTime.tryParse('${value}T00:00:00Z');

    return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
  }

  factory EnergyPrediction.fromJson(Map<String, dynamic> json) {
    final deviceId = json['device_id'];
    final date = json['prediction_date'];
    final energy = json['predicted_energy_wh'];
    final model = json['model_name'];
    final createdAt = json['created_at'];

    if (deviceId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(deviceId)) {
      throw const FormatException('Perangkat tidak valid');
    }

    if (date is! String || !_validDate(date)) {
      throw const FormatException('Tanggal target tidak valid');
    }

    if (energy is! num ||
        !energy.isFinite ||
        energy < 0 ||
        !energy.toDouble().isFinite) {
      throw const FormatException('Nilai prediksi tidak valid');
    }

    if (model is! String || model.trim().isEmpty) {
      throw const FormatException('Nama model tidak valid');
    }

    if (createdAt is! String) {
      throw const FormatException('Waktu prediksi tidak valid');
    }

    // Wajib timestamp dengan zona waktu agar konversi WIB tidak ambigu.
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T'
      r'(\d{2}):(\d{2}):(\d{2})'
      r'(?:\.\d+)?'
      r'(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(createdAt);

    if (match == null ||
        !_validDate(match.group(1)!) ||
        int.parse(match.group(2)!) > 23 ||
        int.parse(match.group(3)!) > 59 ||
        int.parse(match.group(4)!) > 59) {
      throw const FormatException('Waktu prediksi tidak valid');
    }

    final zone = match.group(5)!;

    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4, 6)) > 59)) {
      throw const FormatException('Zona waktu tidak valid');
    }

    final parsedTimestamp = DateTime.tryParse(createdAt);

    if (parsedTimestamp == null) {
      throw const FormatException('Waktu prediksi tidak valid');
    }

    return EnergyPrediction(
      deviceId: deviceId,
      predictionDate: date,
      predictedEnergyWh: energy.toDouble(),
      modelName: model.trim(),
      createdAt: parsedTimestamp.toUtc(),
    );
  }
}
