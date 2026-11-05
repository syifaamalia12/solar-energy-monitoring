import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/history_report.dart';
import '../models/sensor_reading.dart';
import '../services/history_report_service.dart';
import '../utils/measurement_format.dart';
import '../widgets/app_states.dart';

enum _HistoryPeriod { daily, weekly, monthly }

class HistoryReportScreen extends StatefulWidget {
  const HistoryReportScreen({super.key, required this.service, this.now});

  final HistoryReportService service;
  final DateTime Function()? now;

  @override
  State<HistoryReportScreen> createState() => _HistoryReportScreenState();
}

class _HistoryReportScreenState extends State<HistoryReportScreen> {
  _HistoryPeriod _period = _HistoryPeriod.daily;

  late DateTime _selectedDate;
  late Future<HistoryReport> _future;

  HistoryReport? _report;
  HistoryReadingPage? _page;
  List<SensorReading> _readings = [];

  int _requestId = 0;
  bool _loadingMore = false;
  String? _pageError;

  DateTime _todayWib() {
    final time = (widget.now?.call() ?? DateTime.now()).toUtc().add(
      const Duration(hours: 7),
    );

    return DateTime.utc(time.year, time.month, time.day);
  }

  String _dateKey(DateTime date) {
    return date.toIso8601String().substring(0, 10);
  }

  String _displayDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _readingTime(DateTime timestamp) {
    final time = timestamp.toUtc().add(const Duration(hours: 7));

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  DateTime get _rangeStart {
    switch (_period) {
      case _HistoryPeriod.daily:
        return _selectedDate;
      case _HistoryPeriod.weekly:
        return _selectedDate.subtract(
          Duration(days: _selectedDate.weekday - DateTime.monday),
        );
      case _HistoryPeriod.monthly:
        return DateTime.utc(_selectedDate.year, _selectedDate.month);
    }
  }

  DateTime get _rangeEnd {
    switch (_period) {
      case _HistoryPeriod.daily:
        return _selectedDate;
      case _HistoryPeriod.weekly:
        return _rangeStart.add(const Duration(days: 6));
      case _HistoryPeriod.monthly:
        return DateTime.utc(_selectedDate.year, _selectedDate.month + 1, 0);
    }
  }

  String _periodLabel(_HistoryPeriod period) {
    return switch (period) {
      _HistoryPeriod.daily => 'Harian',
      _HistoryPeriod.weekly => 'Mingguan',
      _HistoryPeriod.monthly => 'Bulanan',
    };
  }

  String get _selectionLabel {
    if (_period == _HistoryPeriod.daily) {
      return _displayDate(_selectedDate);
    }

    return '${_displayDate(_rangeStart)} – ${_displayDate(_rangeEnd)}';
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = _todayWib();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant HistoryReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.service != widget.service) {
      _future = _fetch();
    }
  }

  Future<HistoryReport> _fetch() {
    final requestId = ++_requestId;
    final service = widget.service;
    final daily = _period == _HistoryPeriod.daily;
    final start = _dateKey(_rangeStart);
    final end = _dateKey(_rangeEnd);

    _report = null;
    _page = null;
    _readings = [];
    _loadingMore = false;
    _pageError = null;

    final future =
        Future<HistoryReport>.sync(() {
          return daily
              ? service.fetchDay(date: start)
              : service.fetchPeriod(startDate: start, endDate: end);
        }).then((report) {
          if (report.startDate != start || report.endDate != end) {
            throw const HistoryReportApiException(
              'Rentang data dari server tidak sesuai dengan pilihan.',
            );
          }

          if (mounted && requestId == _requestId) {
            _report = report;
            _page = report.firstPage;
            _readings = [...?report.firstPage?.readings];
          }

          return report;
        });

    future.ignore();
    return future;
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  void _selectPeriod(_HistoryPeriod period) {
    if (period == _period) return;

    setState(() {
      _period = period;
      _future = _fetch();
    });
  }

  DateTime _shiftedDate(int direction) {
    switch (_period) {
      case _HistoryPeriod.daily:
        return _selectedDate.add(Duration(days: direction));
      case _HistoryPeriod.weekly:
        return _selectedDate.add(Duration(days: direction * 7));
      case _HistoryPeriod.monthly:
        return DateTime.utc(
          _selectedDate.year,
          _selectedDate.month + direction,
        );
    }
  }

  bool get _canMovePrevious {
    return _shiftedDate(-1).year >= 2000;
  }

  bool get _canMoveNext {
    final today = _todayWib();

    switch (_period) {
      case _HistoryPeriod.daily:
        return _selectedDate.isBefore(today);
      case _HistoryPeriod.weekly:
        return _rangeStart
            .add(const Duration(days: 7))
            .isBefore(today.add(const Duration(days: 1)));
      case _HistoryPeriod.monthly:
        return DateTime.utc(
          _selectedDate.year,
          _selectedDate.month + 1,
        ).isBefore(today.add(const Duration(days: 1)));
    }
  }

  void _moveDate(int direction) {
    if (direction > 0 && !_canMoveNext) return;
    if (direction < 0 && !_canMovePrevious) return;

    var date = _shiftedDate(direction);
    final today = _todayWib();

    if (date.isAfter(today)) date = today;

    setState(() {
      _selectedDate = date;
      _future = _fetch();
    });
  }

  Future<void> _pickDate() async {
    final today = _todayWib();

    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: _period == _HistoryPeriod.daily
          ? 'Pilih tanggal'
          : 'Pilih tanggal dalam minggu atau bulan',
    );

    if (!mounted || chosen == null) return;

    final date = DateTime.utc(chosen.year, chosen.month, chosen.day);
    if (date == _selectedDate) return;

    setState(() {
      _selectedDate = date;
      _future = _fetch();
    });
  }

  String _errorMessage(Object error) {
    return error is HistoryReportApiException
        ? error.message
        : 'Riwayat gagal dimuat. Silakan coba lagi.';
  }

  Future<void> _loadMore() async {
    final page = _page;
    final report = _report;

    if (_loadingMore ||
        page == null ||
        report == null ||
        !page.hasMore ||
        _period != _HistoryPeriod.daily) {
      return;
    }

    final requestId = _requestId;
    final expectedOffset = page.nextOffset!;
    final service = widget.service;

    setState(() {
      _loadingMore = true;
      _pageError = null;
    });

    try {
      final nextPage = await service.fetchReadingPage(
        date: page.date,
        offset: expectedOffset,
        snapshot: page.snapshot,
      );

      if (!mounted || requestId != _requestId) return;

      if (nextPage.date != page.date ||
          nextPage.snapshot != page.snapshot ||
          nextPage.offset != expectedOffset) {
        throw const HistoryReportApiException(
          'Halaman pembacaan tidak sesuai. Muat ulang riwayat.',
        );
      }

      final ids = _readings.map((row) => row.readingId).toSet();

      for (final row in nextPage.readings) {
        if (!ids.add(row.readingId)) {
          throw const HistoryReportApiException(
            'Ditemukan pembacaan duplikat. Muat ulang riwayat.',
          );
        }
      }

      if (_readings.isNotEmpty &&
          nextPage.readings.isNotEmpty &&
          _readings.last.timestamp.isBefore(
            nextPage.readings.first.timestamp,
          )) {
        throw const HistoryReportApiException(
          'Urutan halaman pembacaan tidak sesuai. Muat ulang riwayat.',
        );
      }

      setState(() {
        _readings = [..._readings, ...nextPage.readings];
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;

      setState(() {
        _loadingMore = false;
        _pageError = _errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildControls(),
        const SizedBox(height: 10),
        FutureBuilder<HistoryReport>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoading(message: 'Memuat riwayat energi...');
            }

            if (snapshot.hasError) {
              return AppErrorState(
                message: _errorMessage(snapshot.error!),
                onRetry: _reload,
              );
            }

            return _buildReport(snapshot.data!);
          },
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(12) / 12;
                final useSingleRow =
                    constraints.maxWidth >= 280 && textScale <= 1.2;

                Widget chip(_HistoryPeriod period) {
                  final selected = _period == period;

                  return ChoiceChip(
                    key: ValueKey('report-period-${period.name}'),
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(
                        _periodLabel(period),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF12477E),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: const Color(0xFF0866FF),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF0866FF)
                          : const Color(0xFFDCE6F5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onSelected: (_) => _selectPeriod(period),
                  );
                }

                if (useSingleRow) {
                  return Row(
                    children: [
                      for (final period in _HistoryPeriod.values) ...[
                        if (period != _HistoryPeriod.daily)
                          const SizedBox(width: 6),
                        Expanded(child: chip(period)),
                      ],
                    ],
                  );
                }

                return Column(
                  children: [
                    for (final period in _HistoryPeriod.values)
                      SizedBox(width: double.infinity, child: chip(period)),
                  ],
                );
              },
            ),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('report-previous-date'),
                  tooltip: 'Periode sebelumnya',
                  onPressed: _canMovePrevious ? () => _moveDate(-1) : null,
                  icon: const Icon(Icons.chevron_left, size: 22),
                ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('report-pick-date'),
                    onPressed: _pickDate,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_month_outlined, size: 17),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _selectionLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('report-next-date'),
                  tooltip: 'Periode berikutnya',
                  onPressed: _canMoveNext ? () => _moveDate(1) : null,
                  icon: const Icon(Icons.chevron_right, size: 22),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(HistoryReport report) {
    final summary = report.summary;
    final hasReadings = summary.hasReadings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Grafik Riwayat Produksi',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _period == _HistoryPeriod.daily
                      ? 'Total energi per jam (Wh) • WIB'
                      : 'Total energi per hari (Wh) • WIB',
                  style: const TextStyle(
                    color: Color(0xFF75839A),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 10),
                if (hasReadings)
                  _ReportChart(buckets: report.buckets)
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Belum ada pembacaan pada periode ini.',
                        key: ValueKey('report-empty'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                  'Sentuh batang untuk detail. '
                  'Tanpa pembacaan tidak berarti energi nol.',
                  style: TextStyle(color: Color(0xFF75839A), fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ringkasan ${_periodLabel(_period)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _summaryRow(
                  Icons.bolt,
                  const Color(0xFFE5A000),
                  'Total energi',
                  hasReadings
                      ? '${formatMeasurement(summary.totalEnergyWh)} Wh'
                      : '-- Wh',
                  'report-total-energy',
                ),
                const Divider(height: 14),
                _summaryRow(
                  Icons.flash_on,
                  const Color(0xFF0866FF),
                  'Rata-rata daya',
                  hasReadings
                      ? '${formatMeasurement(summary.averagePowerW)} W'
                      : '-- W',
                  'report-average-power',
                ),
                const Divider(height: 14),
                _summaryRow(
                  Icons.electric_bolt,
                  const Color(0xFFFF3868),
                  'Rata-rata tegangan',
                  hasReadings
                      ? '${formatMeasurement(summary.averageVoltageV, decimals: 2)} V'
                      : '-- V',
                  'report-average-voltage',
                ),
                const Divider(height: 14),
                _summaryRow(
                  Icons.electrical_services,
                  const Color(0xFF14A75B),
                  'Rata-rata arus',
                  hasReadings
                      ? '${formatMeasurement(summary.averageCurrentA)} A'
                      : '-- A',
                  'report-average-current',
                ),
                const SizedBox(height: 8),
                Text(
                  '${summary.readingCount} pembacaan dalam rekap.',
                  style: const TextStyle(
                    color: Color(0xFF75839A),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Rekap seluruh sampel periode dari backend, '
          'bukan hanya baris tabel yang dimuat.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 10),
        ),
        const SizedBox(height: 12),
        Text(
          _period == _HistoryPeriod.daily
              ? 'Data Harian'
              : 'Rekap Energi Harian',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_period == _HistoryPeriod.daily)
          _buildReadings()
        else
          _buildDailyTable(report.buckets),
        const SizedBox(height: 10),
        const Text(
          'Data dari API; server masih dapat berisi data pengujian. '
          'Rata-rata berdasarkan sampel, bukan bobot durasi.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 10),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('report-refresh'),
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
        ),
      ],
    );
  }

  Widget _summaryRow(
    IconData icon,
    Color color,
    String label,
    String value,
    String key,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(
            value,
            key: ValueKey(key),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _table(List<DataColumn> columns, List<DataRow> rows) {
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
                columns: columns,
                rows: rows,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadings() {
    final page = _page;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_readings.isEmpty)
          const Text(
            'Tidak ada pembacaan dalam snapshot tabel ini.',
            style: TextStyle(fontSize: 12),
          )
        else
          _table(
            const [
              DataColumn(label: Text('Waktu (WIB)')),
              DataColumn(label: Text('V'), numeric: true),
              DataColumn(label: Text('A'), numeric: true),
              DataColumn(label: Text('W'), numeric: true),
              DataColumn(label: Text('Wh/interval'), numeric: true),
            ],
            [
              for (final row in _readings)
                DataRow(
                  key: ValueKey('report-reading-${row.readingId}'),
                  cells: [
                    DataCell(Text(_readingTime(row.timestamp))),
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
        const SizedBox(height: 8),
        Text(
          '${_readings.length} pembacaan dimuat, terbaru ke terlama.',
          key: const ValueKey('report-loaded-count'),
          style: const TextStyle(color: Color(0xFF75839A), fontSize: 11),
        ),
        if (page != null && !page.hasMore) ...[
          const SizedBox(height: 4),
          const Text(
            'Seluruh pembacaan dalam snapshot tabel ini sudah dimuat.',
            style: TextStyle(color: Color(0xFF75839A), fontSize: 10),
          ),
        ],
        if (_pageError != null) ...[
          const SizedBox(height: 8),
          Text(
            _pageError!,
            style: const TextStyle(color: Color(0xFFB3261E), fontSize: 12),
          ),
        ],
        if (page != null && page.hasMore) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('report-load-more'),
            onPressed: _loadingMore ? null : _loadMore,
            icon: _loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: Text(
              _loadingMore
                  ? 'Memuat pembacaan...'
                  : _pageError != null
                  ? 'Coba lagi memuat'
                  : 'Muat lebih banyak',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDailyTable(List<HistoryBucket> buckets) {
    return _table(
      const [
        DataColumn(label: Text('Tanggal (WIB)')),
        DataColumn(label: Text('Energi (Wh)'), numeric: true),
        DataColumn(label: Text('Pembacaan'), numeric: true),
      ],
      [
        for (final bucket in buckets)
          DataRow(
            cells: [
              DataCell(
                Text(_displayDate(DateTime.parse('${bucket.date}T00:00:00Z'))),
              ),
              DataCell(
                Text(
                  bucket.hasReadings
                      ? formatMeasurement(bucket.totalEnergyWh)
                      : '--',
                ),
              ),
              DataCell(Text('${bucket.readingCount}')),
            ],
          ),
      ],
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({required this.buckets});

  final List<HistoryBucket> buckets;

  String _label(HistoryBucket bucket) {
    final hour = bucket.hour;

    if (hour != null) {
      return '${hour.toString().padLeft(2, '0')}:00';
    }

    final parts = bucket.date.split('-');
    return '${parts[2]}/${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const Text('Data grafik belum tersedia.');
    }

    final peak = buckets.fold<double>(
      0,
      (maximum, bucket) => bucket.hasReadings && bucket.totalEnergyWh > maximum
          ? bucket.totalEnergyWh
          : maximum,
    );

    final scale = peak > 0 ? peak : 1.0;
    final labelStep = buckets.first.hour != null
        ? 6
        : buckets.length <= 7
        ? 1
        : 7;

    return SizedBox(
      height: 170,
      child: BarChart(
        key: const ValueKey('report-chart'),
        BarChartData(
          minY: 0,
          maxY: 1.1,
          alignment: BarChartAlignment.spaceAround,
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
                reservedSize: 62,
                interval: 0.25,
                maxIncluded: false,
                getTitlesWidget: (value, meta) => Text(
                  formatMeasurement(value * scale),
                  style: const TextStyle(color: Color(0xFF75839A), fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final index = value.round();

                  if ((value - index).abs() > 0.001 ||
                      index < 0 ||
                      index >= buckets.length ||
                      index % labelStep != 0) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _label(buckets[index]),
                      style: const TextStyle(
                        color: Color(0xFF75839A),
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final bucket = buckets[group.x];
                final time = bucket.hour == null ? '' : ' ${_label(bucket)}';

                final value = bucket.hasReadings
                    ? '${formatMeasurement(bucket.totalEnergyWh)} Wh'
                    : 'Tidak ada pembacaan';

                return BarTooltipItem(
                  '${bucket.date}$time WIB\n'
                  '$value\n'
                  '${bucket.readingCount} pembacaan',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          barGroups: [
            for (var index = 0; index < buckets.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: buckets[index].hasReadings
                        ? buckets[index].totalEnergyWh / scale
                        : 0,
                    color: buckets[index].hasReadings
                        ? const Color(0xFF0866FF)
                        : Colors.transparent,
                    width: buckets.length <= 7 ? 20 : 6,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
