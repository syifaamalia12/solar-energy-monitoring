class DailyEnergy {
  const DailyEnergy({
    required this.date,
    required this.totalEnergyWh,
    required this.readingCount,
  });

  // Tanggal kalender WIB dari backend, bukan timestamp UTC.
  final String date;
  final double totalEnergyWh;
  final int readingCount;

  factory DailyEnergy.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final energy = json['total_energy_wh'];
    final count = json['reading_count'];

    if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw const FormatException('Tanggal tidak valid');
    }

    final parsed = DateTime.tryParse('${date}T00:00:00Z');

    if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Tanggal tidak valid');
    }

    if (energy is! num ||
        !energy.isFinite ||
        energy < 0 ||
        !energy.toDouble().isFinite) {
      throw const FormatException('Energi tidak valid');
    }

    if (count is! int || count < 0) {
      throw const FormatException('Jumlah pembacaan tidak valid');
    }

    return DailyEnergy(
      date: date,
      totalEnergyWh: energy.toDouble(),
      readingCount: count,
    );
  }
}
