class DashboardData {
  const DashboardData({
    required this.deviceId,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.totalEnergyWh,
    required this.summaryDate,
    required this.readingTimestamp,
    required this.isTestData,
  });

  final String deviceId;
  final double voltageV;
  final double currentA;
  final double powerW;

  // Total energi satu hari, bukan energi dari satu pembacaan.
  final double totalEnergyWh;

  // Tanggal rekap energi dalam format YYYY-MM-DD.
  final String summaryDate;

  // Waktu pembacaan sensor, bukan waktu aplikasi mengambil data.
  final DateTime readingTimestamp;

  final bool isTestData;
}
