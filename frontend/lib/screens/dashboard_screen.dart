import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/dashboard_data.dart';
import '../services/dashboard_service.dart';
import '../widgets/app_states.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.service});

  final DashboardService? service;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late final DashboardService _service;
  late Future<DashboardData?> _future;

  Timer? _timer;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _service =
        widget.service ?? MockDashboardService(deviceId: AppConfig.deviceId);

    _future = _fetch();

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  Future<DashboardData?> _fetch() async {
    _isFetching = true;

    try {
      return await _service.fetchDashboard();
    } finally {
      _isFetching = false;
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard Monitoring',
          key: const ValueKey('page-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        FutureBuilder<DashboardData?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoading();
            }

            if (snapshot.hasError) {
              return AppErrorState(
                message: 'Data monitoring gagal dimuat. Silakan coba lagi.',
                onRetry: _reload,
              );
            }

            final data = snapshot.data;

            if (data == null) {
              return Column(
                children: [
                  const AppEmptyState(
                    message: 'Data monitoring belum tersedia.',
                  ),
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
        ),
      ],
    );
  }

  Widget _buildData(BuildContext context, DashboardData data) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.isTestData) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Data pengujian\n'
                    'Angka di bawah hanya contoh tampilan, '
                    'bukan pembacaan sensor atau hasil API.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 320 ? 2 : 1;
            final cardWidth =
                (constraints.maxWidth - (columns - 1) * 12) / columns;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  width: cardWidth,
                  label: 'Tegangan',
                  value: data.voltageV.toStringAsFixed(2),
                  unit: 'V',
                  icon: Icons.bolt_outlined,
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Arus',
                  value: data.currentA.toStringAsFixed(4),
                  unit: 'A',
                  icon: Icons.electrical_services_outlined,
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Daya',
                  value: data.powerW.toStringAsFixed(4),
                  unit: 'W',
                  icon: Icons.solar_power_outlined,
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Energi harian',
                  value: data.totalEnergyWh.toStringAsFixed(4),
                  unit: 'Wh',
                  icon: Icons.energy_savings_leaf_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text('Tanggal rekap energi (WIB): ${data.summaryDate}'),
        const SizedBox(height: 8),
        Text(
          data.isTestData
              ? 'Simulasi diambil ulang setiap 60 detik. '
                    'Nilai contoh tetap sama.'
              : 'Data diambil ulang setiap 60 detik.',
        ),
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.schedule_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.isTestData
                            ? 'Waktu pembacaan contoh'
                            : 'Waktu pembacaan sensor',
                      ),
                      const SizedBox(height: 4),
                      Text(_formatWib(data.readingTimestamp)),
                      if (data.isTestData) ...[
                        const SizedBox(height: 8),
                        const Text('Belum terhubung ke API.'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
  });

  final double width;
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.primary, size: 28),
              const SizedBox(height: 12),
              Text(label, style: textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                '$value $unit',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
