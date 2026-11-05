import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/dashboard_data.dart';
import '../models/energy_prediction.dart';
import '../services/api_dashboard_service.dart';
import '../services/dashboard_service.dart';
import '../services/prediction_service.dart';
import '../utils/measurement_format.dart';
import '../widgets/app_states.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.service,
    this.now,
    this.predictionService,
    this.onOpenPrediction,
  });

  final DashboardService? service;
  final DateTime Function()? now;
  final PredictionService? predictionService;
  final VoidCallback? onOpenPrediction;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late final DashboardService _service;
  late Future<DashboardData?> _future;

  Timer? _timer;
  bool _isFetching = false;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Aplikasi menerima layanan API dari main.dart.
    // Fallback dipertahankan untuk tes tanpa service.
    _service =
        widget.service ?? MockDashboardService(deviceId: AppConfig.deviceId);

    _future = _fetch();

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  Future<DashboardData?> _fetch() {
    _isFetching = true;

    final future = Future<DashboardData?>.sync(() => _service.fetchDashboard())
        .whenComplete(() {
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

  String _formatWib(DateTime timestamp) {
    final time = timestamp.toUtc().add(const Duration(hours: 7));

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(time.day)}/${two(time.month)}/${time.year}, '
        '${two(time.hour)}:${two(time.minute)} WIB';
  }

  String _todayWib() {
    return _now()
        .toUtc()
        .add(const Duration(hours: 7))
        .toIso8601String()
        .substring(0, 10);
  }

  bool _isStale(DateTime timestamp) {
    return _now().toUtc().difference(timestamp.toUtc()) >
        const Duration(minutes: 3);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoading();
        }

        if (snapshot.hasError) {
          final error = snapshot.error;

          return AppErrorState(
            message: error is DashboardApiException
                ? error.message
                : 'Data monitoring gagal dimuat. Silakan coba lagi.',
            onRetry: _reload,
          );
        }

        final data = snapshot.data;

        if (data == null) {
          return Column(
            children: [
              const AppEmptyState(message: 'Data monitoring belum tersedia.'),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          );
        }

        return _buildData(context, data);
      },
    );
  }

  Widget _buildData(BuildContext context, DashboardData data) {
    final stale = _isStale(data.readingTimestamp);
    final energy = data.hasDailyReadings
        ? formatMeasurement(data.totalEnergyWh)
        : '--';

    final statusColor = stale
        ? const Color(0xFF996000)
        : const Color(0xFF087E58);
    final predictionService = widget.predictionService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.solar_power,
                    color: Color(0xFF12477E),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status Perangkat',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              stale
                                  ? 'Belum ada data terbaru'
                                  : 'Pembacaan terbaru tersedia',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        data.isTestData
                            ? 'Waktu pembacaan contoh'
                            : 'Waktu pembacaan terakhir',
                        style: const TextStyle(
                          color: Color(0xFF75839A),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatWib(data.readingTimestamp),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0866FF), Color(0xFF12477E)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Produksi Energi Harian',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFFFD54F),
                    size: 32,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          energy,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Wh',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tanggal rekap energi (WIB): ${data.summaryDate}',
                style: const TextStyle(color: Color(0xFFDCEAFF), fontSize: 11),
              ),
              if (!data.hasDailyReadings) ...[
                const SizedBox(height: 6),
                Text(
                  data.summaryDate == _todayWib()
                      ? 'Belum ada data energi hari ini.'
                      : 'Belum ada pembacaan pada tanggal rekap tersebut.',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
            final columns = constraints.maxWidth >= 300 && textScale <= 1.2
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard(
                  width: width,
                  label: 'Tegangan',
                  value: formatMeasurement(data.voltageV, decimals: 2),
                  unit: 'V',
                  icon: Icons.bolt_outlined,
                  color: const Color(0xFFFF3868),
                  background: const Color(0xFFFFEBF1),
                ),
                _MetricCard(
                  width: width,
                  label: 'Arus',
                  value: formatMeasurement(data.currentA),
                  unit: 'A',
                  icon: Icons.electrical_services_outlined,
                  color: const Color(0xFF14A75B),
                  background: const Color(0xFFE9FAEF),
                ),
                _MetricCard(
                  width: width,
                  label: 'Daya',
                  value: formatMeasurement(data.powerW),
                  unit: 'W',
                  icon: Icons.flash_on_rounded,
                  color: const Color(0xFFE5A000),
                  background: const Color(0xFFFFF7DD),
                ),
                _MetricCard(
                  width: width,
                  label: 'Energi harian',
                  value: energy,
                  unit: 'Wh',
                  icon: Icons.battery_charging_full_rounded,
                  color: const Color(0xFF0866FF),
                  background: const Color(0xFFEDF4FF),
                ),
              ],
            );
          },
        ),
        if (stale) ...[
          const SizedBox(height: 12),
          const Text(
            'Pembacaan terakhir sudah lebih dari 3 menit. '
            'Kondisi ini belum memastikan perangkat offline.',
            style: TextStyle(color: Color(0xFF79643A), fontSize: 11),
          ),
        ],
        if (predictionService != null) ...[
          const SizedBox(height: 12),
          _HomePredictionCard(
            // Setiap siklus pemuatan Dashboard membuat ringkasan baru.
            key: ObjectKey(_future),
            service: predictionService,
            onOpenPrediction: widget.onOpenPrediction,
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF4FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                data.isTestData
                    ? Icons.science_outlined
                    : Icons.cloud_done_outlined,
                color: const Color(0xFF0866FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.isTestData
                      ? 'Data pengujian\n'
                            'Angka berikut hanya contoh tampilan, '
                            'bukan pembacaan sensor atau hasil API.'
                      : 'Data dari API\n'
                            'Menampilkan pembacaan terakhir yang tersedia. '
                            'Data pada server masih dapat berupa data pengujian.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF405B80),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (data.isTestData) ...[
          const SizedBox(height: 6),
          const Text('Belum terhubung ke API.'),
        ],
        const SizedBox(height: 10),
        Text(
          data.isTestData
              ? 'Simulasi diambil ulang setiap 60 detik. '
                    'Nilai contoh tetap sama.'
              : 'Data diambil ulang setiap 60 detik saat Dashboard aktif.',
          style: const TextStyle(color: Color(0xFF75839A), fontSize: 11),
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
}

class _HomePredictionCard extends StatefulWidget {
  const _HomePredictionCard({
    super.key,
    required this.service,
    this.onOpenPrediction,
  });

  final PredictionService service;
  final VoidCallback? onOpenPrediction;

  @override
  State<_HomePredictionCard> createState() => _HomePredictionCardState();
}

class _HomePredictionCardState extends State<_HomePredictionCard> {
  late Future<EnergyPrediction?> _future;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<EnergyPrediction?> _fetch() {
    _isFetching = true;

    final future =
        Future<EnergyPrediction?>.sync(
          () => widget.service.fetchLatestPrediction(),
        ).whenComplete(() {
          _isFetching = false;
        });

    future.ignore();
    return future;
  }

  void _retry() {
    if (!mounted || _isFetching) return;

    setState(() {
      _future = _fetch();
    });
  }

  String _targetDate(String date) {
    final parts = date.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('home-prediction-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  color: Color(0xFF0866FF),
                  size: 26,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ringkasan Prediksi',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<EnergyPrediction?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Memuat ringkasan prediksi...',
                          style: TextStyle(
                            color: Color(0xFF75839A),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (snapshot.hasError) {
                  final error = snapshot.error;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ringkasan prediksi gagal dimuat.',
                        style: TextStyle(
                          color: Color(0xFF996000),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        error is PredictionApiException
                            ? error.message
                            : 'Silakan coba kembali.',
                        style: const TextStyle(
                          color: Color(0xFF75839A),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        key: const ValueKey('home-prediction-retry'),
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Ulangi prediksi'),
                      ),
                    ],
                  );
                }

                final prediction = snapshot.data;

                if (prediction == null) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prediksi energi belum tersedia.',
                        key: ValueKey('home-prediction-empty'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Belum ada hasil prediksi yang tersedia dari backend.',
                        style: TextStyle(
                          color: Color(0xFF75839A),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatMeasurement(prediction.predictedEnergyWh)} Wh',
                      key: const ValueKey('home-prediction-energy'),
                      style: const TextStyle(
                        color: Color(0xFF0866FF),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tanggal target: '
                      '${_targetDate(prediction.predictionDate)}',
                      key: const ValueKey('home-prediction-target-date'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Model: ${prediction.modelName}',
                      style: const TextStyle(
                        color: Color(0xFF75839A),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tanggal target mengikuti hasil backend, '
                      'tidak selalu untuk besok.',
                      style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
                    ),
                  ],
                );
              },
            ),
            if (widget.onOpenPrediction != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('home-open-prediction'),
                  onPressed: widget.onOpenPrediction,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Lihat prediksi'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.background,
  });

  final double width;
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
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
                    const SizedBox(height: 5),
                    Text(
                      '$value $unit',
                      style: const TextStyle(
                        color: Color(0xFF18243A),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
}
