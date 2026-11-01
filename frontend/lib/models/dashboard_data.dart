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
    this.readingCount = 0,
  });

  final String deviceId;
  final double voltageV;
  final double currentA;
  final double powerW;

  // Total energi satu hari, bukan energi satu interval.
  final double totalEnergyWh;

  // Tanggal rekap berdasarkan WIB.
  final String summaryDate;

  // Waktu pembacaan, bukan waktu permintaan API.
  final DateTime readingTimestamp;

  final bool isTestData;
  final int readingCount;

  bool get hasDailyReadings => readingCount > 0;
}
