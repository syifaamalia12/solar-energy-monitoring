import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/dashboard_data.dart';
import '../models/sensor_reading.dart';
import '../services/api_dashboard_service.dart';
import '../services/dashboard_service.dart';
import '../services/monitoring_service.dart';
import '../utils/measurement_format.dart';
import '../widgets/app_states.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({
    super.key,
    required this.dashboardService,
    required this.service,
  });

  final DashboardService? dashboardService;
  final MonitoringService? service;

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  late Future<_MonitoringData> _future;

  Timer? _timer;
  bool _isFetching = false;
  bool _showGraph = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _future = _fetch();

    final lifecycle = WidgetsBinding.instance.lifecycleState;

    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  Future<_MonitoringData> _fetch() {
    _isFetching = true;

    final future =
        Future<_MonitoringData>.sync(() async {
          final dashboardService = widget.dashboardService;
          final service = widget.service;

          if (dashboardService == null || service == null) {
            throw const MonitoringApiException(
              'Layanan monitoring belum dikonfigurasi.',
            );
          }

          final results = await Future.wait<Object?>([
            dashboardService.fetchDashboard(),
            service.fetchReadings(limit: 100),
          ]);

          return _MonitoringData(
            dashboard: results[0] as DashboardData?,
            readings: results[1] as List<SensorReading>,
          );
        }).whenComplete(() {
          _isFetching = false;
        });

    future.ignore();
    return future;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.refreshInterval, (_) => _reload());
  }

  void _reload() {
    if (!mounted || _isFetching) return;

    setState(() {
      _future = _fetch();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _timeWib(DateTime timestamp) {
    final time = timestamp.toUtc().add(const Duration(hours: 7));

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(time.day)}/${two(time.month)}/${time.year}, '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)} WIB';
  }

  String _clockWib(DateTime timestamp) {
    final time = timestamp.toUtc().add(const Duration(hours: 7));

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Real-time'),
              selected: !_showGraph,
              onSelected: (_) {
                setState(() => _showGraph = false);
              },
            ),
            ChoiceChip(
              label: const Text('Grafik'),
              selected: _showGraph,
              onSelected: (_) {
                setState(() => _showGraph = true);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Data diambil ulang setiap 60 detik saat Monitoring aktif.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
        ),
        const SizedBox(height: 12),
        FutureBuilder<_MonitoringData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoading(message: 'Memuat monitoring...');
            }

            if (snapshot.hasError) {
              final error = snapshot.error;

              return AppErrorState(
                message: error is MonitoringApiException
                    ? error.message
                    : error is DashboardApiException
                    ? error.message
                    : 'Monitoring gagal dimuat. Silakan coba lagi.',
                onRetry: _reload,
              );
            }

            final data = snapshot.data!;

            if (data.dashboard == null && data.readings.isEmpty) {
              return Column(
                children: [
                  const AppEmptyState(
                    message: 'Data monitoring belum tersedia.',
                  ),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang'),
                  ),
                ],
              );
            }

            return _buildData(data);
          },
        ),
      ],
    );
  }

  Widget _buildData(_MonitoringData data) {
    final dashboard = data.dashboard;
    final latest = data.readings.isEmpty ? null : data.readings.last;
    final timestamp = dashboard?.readingTimestamp ?? latest?.timestamp;
    final voltage = dashboard?.voltageV ?? latest?.voltageV;
    final current = dashboard?.currentA ?? latest?.currentA;
    final power = dashboard?.powerW ?? latest?.powerW;

    final stale =
        timestamp != null &&
        DateTime.now().toUtc().difference(timestamp.toUtc()) >
            const Duration(minutes: 3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (timestamp != null) ...[
          Text(
            stale ? 'Belum ada data terbaru' : 'Pembacaan terakhir tersedia',
            style: TextStyle(
              color: stale ? const Color(0xFF996000) : const Color(0xFF087E58),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(_timeWib(timestamp), style: const TextStyle(fontSize: 11)),
          if (stale) ...[
            const SizedBox(height: 4),
            const Text(
              'Pembacaan sudah lebih dari 3 menit; '
              'ini belum memastikan perangkat offline.',
              style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
        ],
        if (!_showGraph) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = constraints.maxWidth >= 300 && textScale <= 1.2
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metric(
                    width,
                    'Tegangan',
                    voltage == null
                        ? '-- V'
                        : '${formatMeasurement(voltage, decimals: 2)} V',
                    Icons.bolt,
                    const Color(0xFFFF3868),
                  ),
                  _metric(
                    width,
                    'Arus',
                    current == null
                        ? '-- A'
                        : '${formatMeasurement(current)} A',
                    Icons.electrical_services,
                    const Color(0xFF14A75B),
                  ),
                  _metric(
                    width,
                    'Daya',
                    power == null ? '-- W' : '${formatMeasurement(power)} W',
                    Icons.flash_on,
                    const Color(0xFFE5A000),
                  ),
                  _metric(
                    width,
                    'Energi harian',
                    dashboard != null && dashboard.hasDailyReadings
                        ? '${formatMeasurement(dashboard.totalEnergyWh)} Wh'
                        : '-- Wh',
                    Icons.battery_charging_full,
                    const Color(0xFF0866FF),
                  ),
                ],
              );
            },
          ),
          if (dashboard != null) ...[
            const SizedBox(height: 8),
            Text(
              'Tanggal rekap energi (WIB): ${dashboard.summaryDate}',
              style: const TextStyle(color: Color(0xFF75839A), fontSize: 11),
            ),
            if (!dashboard.hasDailyReadings)
              const Text(
                'Belum ada pembacaan pada tanggal rekap tersebut.',
                style: TextStyle(fontSize: 11),
              ),
          ],
          const SizedBox(height: 12),
        ],

        // Real-time: kartu pengukuran, grafik, dan tabel terbaru.
        // Grafik: fokus grafik dan tabel pembacaan lebih lengkap.
        _buildGraph(data.readings),
        const SizedBox(height: 12),
        Text(
          _showGraph ? 'Data pembacaan' : 'Data Terbaru',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (data.readings.isEmpty)
          const AppEmptyState(
            message: 'Riwayat pembacaan sensor belum tersedia.',
          )
        else
          _buildTable(
            data.readings.reversed.take(_showGraph ? 100 : 5).toList(),
          ),
        const SizedBox(height: 10),
        const Text(
          'Data dari API. Riwayat berisi pembacaan terakhir yang tersedia, '
          'bukan selalu pembacaan hari ini. '
          'Data pada server masih dapat berupa data pengujian.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
        ),
      ],
    );
  }

  Widget _metric(
    double width,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF75839A),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGraph(List<SensorReading> rows) {
    if (rows.isEmpty) {
      return const AppEmptyState(
        message: 'Data grafik monitoring belum tersedia.',
      );
    }

    final peak = rows.fold<double>(
      0,
      (maximum, row) => row.energyWh > maximum ? row.energyWh : maximum,
    );

    // Normalisasi hanya untuk penggambaran.
    // Label sumbu dan tooltip tetap memakai nilai Wh asli.
    final scale = peak > 0 ? peak : 1.0;
    final firstTime = rows.first.timestamp.toUtc();
    final lastTime = rows.last.timestamp.toUtc();
    final spanMilliseconds = lastTime.difference(firstTime).inMilliseconds;
    final hasTimeRange = spanMilliseconds > 0;

    final spots = [
      for (final row in rows)
        FlSpot(
          hasTimeRange
              ? row.timestamp.toUtc().difference(firstTime).inMilliseconds /
                    spanMilliseconds
              : 0.5,
          row.energyWh / scale,
        ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Energi per interval pengukuran',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Energi (Wh), bukan total energi harian.',
              style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 210,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 1,
                  minY: 0,
                  maxY: 1.2,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: 0.25,
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 70,
                        interval: 0.25,
                        maxIncluded: false,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            formatMeasurement(value * scale),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xFF75839A),
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      maxContentWidth: 190,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final row = rows[spot.spotIndex];

                          return LineTooltipItem(
                            '${_timeWib(row.timestamp)}\n'
                            '${formatMeasurement(row.energyWh)} Wh\n'
                            'Interval ${row.intervalSeconds} detik',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: const Color(0xFF0866FF),
                      barWidth: 2,
                      dotData: FlDotData(show: rows.length <= 12),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0x190866FF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 70),
              child: hasTimeRange
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            _clockWib(firstTime),
                            style: const TextStyle(
                              color: Color(0xFF75839A),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _clockWib(
                              firstTime.add(
                                Duration(milliseconds: spanMilliseconds ~/ 2),
                              ),
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF75839A),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _clockWib(lastTime),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xFF75839A),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Text(
                        _clockWib(firstTime),
                        style: const TextStyle(
                          color: Color(0xFF75839A),
                          fontSize: 10,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Waktu (WIB)',
                style: TextStyle(color: Color(0xFF75839A), fontSize: 10),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              hasTimeRange
                  ? '${_timeWib(firstTime)}\nsampai ${_timeWib(lastTime)}'
                  : _timeWib(firstTime),
              style: const TextStyle(color: Color(0xFF75839A), fontSize: 10),
            ),
            const SizedBox(height: 8),
            Text(
              '${rows.length} pembacaan, urutan terlama ke terbaru. '
              'Sentuh grafik untuk melihat waktu dan nilai asli. '
              'Jarak mendatar mengikuti selisih waktu pembacaan; '
              'garis penghubung bukan pembacaan tambahan.',
              style: const TextStyle(color: Color(0xFF75839A), fontSize: 11),
            ),
            if (peak == 0) ...[
              const SizedBox(height: 6),
              const Text(
                'Semua nilai energi interval yang diterima bernilai nol.',
                style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<SensorReading> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
        final rowHeight = (40 * textScale).clamp(40.0, 100.0).toDouble();
        final headingHeight = (42 * textScale).clamp(42.0, 100.0).toDouble();

        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                columnSpacing: 12,
                horizontalMargin: 10,
                headingRowHeight: headingHeight,
                dataRowMinHeight: rowHeight,
                dataRowMaxHeight: rowHeight,
                headingTextStyle: const TextStyle(
                  color: Color(0xFF75839A),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                dataTextStyle: const TextStyle(
                  color: Color(0xFF18243A),
                  fontSize: 11,
                ),
                columns: const [
                  DataColumn(label: Text('Waktu (WIB)')),
                  DataColumn(label: Text('V'), numeric: true),
                  DataColumn(label: Text('A'), numeric: true),
                  DataColumn(label: Text('W'), numeric: true),
                  DataColumn(label: Text('Wh/interval'), numeric: true),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(_timeWib(row.timestamp))),
                        DataCell(
                          Text(formatMeasurement(row.voltageV, decimals: 2)),
                        ),
                        DataCell(Text(formatMeasurement(row.currentA))),
                        DataCell(Text(formatMeasurement(row.powerW))),
                        DataCell(Text(formatMeasurement(row.energyWh))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MonitoringData {
  const _MonitoringData({required this.dashboard, required this.readings});

  final DashboardData? dashboard;
  final List<SensorReading> readings;
}
