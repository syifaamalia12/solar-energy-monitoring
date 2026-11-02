import 'dart:async';

import 'package:flutter/material.dart';

import '../models/energy_prediction.dart';
import '../services/prediction_service.dart';
import '../utils/measurement_format.dart';
import '../widgets/app_states.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key, this.service});

  final PredictionService? service;

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  late Future<EnergyPrediction?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant PredictionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.service != widget.service) {
      _future = _fetch();
    }
  }

  Future<EnergyPrediction?> _fetch() {
    final future = Future<EnergyPrediction?>.sync(() {
      final service = widget.service;

      if (service == null) {
        throw const PredictionApiException(
          'Layanan prediksi belum dikonfigurasi.',
        );
      }

      return service.fetchLatestPrediction();
    });

    // Pasang penanganan segera, sebelum FutureBuilder dibangun ulang.
    // Future asli tetap dikembalikan sehingga FutureBuilder masih
    // menerima data maupun error untuk ditampilkan di halaman.
    future.ignore();

    return future;
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  String _formatDate(String date) {
    final parts = date.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  String _formatWib(DateTime timestamp) {
    final time = timestamp.toUtc().add(const Duration(hours: 7));

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(time.day)}/${two(time.month)}/'
        '${time.year.toString().padLeft(4, '0')}, '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)} WIB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prediksi Energi',
          key: const ValueKey('page-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text('Prediksi produksi energi harian panel surya dalam Wh.'),
        const SizedBox(height: 20),
        FutureBuilder<EnergyPrediction?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoading(message: 'Memuat prediksi energi...');
            }

            if (snapshot.hasError) {
              final error = snapshot.error;

              return AppErrorState(
                message: error is PredictionApiException
                    ? error.message
                    : 'Prediksi energi gagal dimuat. Silakan coba lagi.',
                onRetry: _reload,
              );
            }

            final data = snapshot.data;

            if (data == null) {
              return Column(
                children: [
                  const AppEmptyState(
                    message: 'Prediksi energi belum tersedia.',
                  ),
                  const Text(
                    'Belum ada hasil prediksi yang tersedia dari backend.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('prediction-refresh'),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang'),
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

  Widget _buildData(BuildContext context, EnergyPrediction data) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              Icon(Icons.cloud_done_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Data dari API\n'
                  'Menampilkan hasil prediksi yang tersimpan di server. '
                  'Data pada server masih dapat berupa data pengujian.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.solar_power_outlined,
                    size: 32,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text('Prediksi produksi energi'),
                  const SizedBox(height: 8),
                  Text(
                    '${formatMeasurement(data.predictedEnergyWh)} Wh',
                    key: const ValueKey('prediction-energy'),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Tanggal target prediksi (WIB)'),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(data.predictionDate),
                    key: const ValueKey('prediction-target-date'),
                    style: textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Model prediksi'),
                  const SizedBox(height: 4),
                  Text(
                    data.modelName,
                    key: const ValueKey('prediction-model'),
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  const Text('Waktu prediksi dibuat'),
                  const SizedBox(height: 4),
                  Text(
                    _formatWib(data.createdAt),
                    key: const ValueKey('prediction-created-at'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tanggal target mengikuti hasil backend, '
          'tidak selalu untuk besok.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Nilai ini merupakan prediksi produksi energi panel surya, '
          'bukan konsumsi pengguna atau kapasitas baterai.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Model dijalankan oleh layanan AI. '
          'Aplikasi hanya menampilkan hasilnya.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('prediction-refresh'),
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
        ),
      ],
    );
  }
}
