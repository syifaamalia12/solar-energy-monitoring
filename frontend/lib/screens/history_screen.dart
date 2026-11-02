import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/daily_energy.dart';
import '../services/history_service.dart';
import '../utils/measurement_format.dart';
import '../widgets/app_states.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.service});

  final HistoryService? service;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _days = 7;
  late Future<List<DailyEnergy>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.service != widget.service) {
      _future = _fetch();
    }
  }

  Future<List<DailyEnergy>> _fetch() async {
    final service = widget.service;

    if (service == null) {
      throw const HistoryApiException('Layanan riwayat belum dikonfigurasi.');
    }

    return service.fetchHistory(days: _days);
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  void _selectPeriod(int days) {
    if (days == _days) return;

    setState(() {
      _days = days;
      _future = _fetch();
    });
  }

  String _displayDate(String date) {
    final parts = date.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Riwayat Energi',
          key: const ValueKey('page-title'),
          style: textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text('Periode hari terakhir berdasarkan WIB'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in const [7, 14, 30])
              ChoiceChip(
                key: ValueKey('history-period-$days'),
                label: Text('$days hari'),
                selected: _days == days,
                onSelected: (_) => _selectPeriod(days),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<DailyEnergy>>(
          future: _future,
          builder: (context, snapshot) {
            // Jangan tampilkan data periode lama ketika periode baru dimuat.
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoading(message: 'Memuat riwayat energi...');
            }

            if (snapshot.hasError) {
              final error = snapshot.error;

              return AppErrorState(
                message: error is HistoryApiException
                    ? error.message
                    : 'Riwayat energi gagal dimuat. Silakan coba lagi.',
                onRetry: _reload,
              );
            }

            final rows = snapshot.data ?? const <DailyEnergy>[];

            if (rows.isEmpty) {
              return Column(
                children: [
                  AppEmptyState(
                    message:
                        'Riwayat energi belum tersedia '
                        'untuk $_days hari terakhir.',
                  ),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang'),
                  ),
                ],
              );
            }

            return _buildData(context, rows);
          },
        ),
      ],
    );
  }

  Widget _buildData(BuildContext context, List<DailyEnergy> rows) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Data dari API. Data pada server masih dapat berupa data pengujian.',
        ),
        const SizedBox(height: 8),
        Text(
          'Tersedia ${rows.length} hari dengan pembacaan '
          'dalam $_days hari terakhir.',
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Grafik energi harian', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Energi (Wh)'),
                const SizedBox(height: 20),
                _EnergyChart(rows: rows),
                const SizedBox(height: 12),
                const Text(
                  'Tanggal (WIB). Sentuh batang untuk melihat nilai. '
                  'Geser grafik ke samping jika diperlukan.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Hanya tanggal yang memiliki pembacaan ditampilkan. '
          'Hari tanpa data tidak dianggap sebagai energi nol.',
        ),
        if (rows.every((item) => item.totalEnergyWh == 0)) ...[
          const SizedBox(height: 8),
          const Text(
            'Seluruh energi yang tercatat bernilai 0 Wh. '
            'Batang berada pada garis dasar grafik.',
          ),
        ],
        const SizedBox(height: 20),
        Text('Daftar energi harian', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final item in rows)
          Card(
            key: ValueKey('history-row-${item.date}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_displayDate(item.date)} WIB',
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatMeasurement(item.totalEnergyWh)} Wh',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('${item.readingCount} pembacaan'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
        ),
      ],
    );
  }
}

class _EnergyChart extends StatelessWidget {
  const _EnergyChart({required this.rows});

  final List<DailyEnergy> rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final peak = rows.fold<double>(
      0,
      (maximum, item) => math.max(maximum, item.totalEnergyWh),
    );

    // Skala internal dinormalisasi agar energi yang sangat kecil
    // tetap tergambar. Label dan tooltip tetap memakai nilai Wh asli.
    final scale = peak > 0 ? peak : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = math.max(
          constraints.maxWidth,
          rows.length * 64.0 + 88,
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            height: 260,
            child: BarChart(
              key: const ValueKey('history-chart'),
              BarChartData(
                minY: 0,
                maxY: 1.2,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 0.25,
                ),
                borderData: FlBorderData(show: false),
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
                      reservedSize: 76,
                      interval: 0.25,
                      maxIncluded: false,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          formatMeasurement(value * scale, decimals: 3),
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();

                        if ((value - index).abs() > 0.001 ||
                            index < 0 ||
                            index >= rows.length) {
                          return const SizedBox.shrink();
                        }

                        final parts = rows[index].date.split('-');

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${parts[2]}/${parts[1]}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final item = rows[group.x];

                      return BarTooltipItem(
                        '${item.date}\n'
                        '${formatMeasurement(item.totalEnergyWh)} Wh',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < rows.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: rows[index].totalEnergyWh / scale,
                          color: colors.primary,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                        ),
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
