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

    // FutureBuilder tetap menerima data/error asli.
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
        const Text(
          'Prediksi produksi energi harian panel surya dalam Wh.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 12),
        ),
        const SizedBox(height: 12),
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
              return _buildEmpty();
            }

            return _buildData(context, data);
          },
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppEmptyState(message: 'Prediksi energi belum tersedia.'),
              const Text(
                'Belum ada hasil prediksi yang tersedia dari backend.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF75839A), fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('prediction-refresh'),
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildData(BuildContext context, EnergyPrediction data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0866FF), Color(0xFF12477E)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights_rounded, color: Colors.white, size: 26),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Prediksi produksi energi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${formatMeasurement(data.predictedEnergyWh)} Wh',
                key: const ValueKey('prediction-energy'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Tanggal target prediksi (WIB)',
                style: TextStyle(color: Color(0xFFDCEAFF), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(data.predictionDate),
                key: const ValueKey('prediction-target-date'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_graph_rounded,
                        color: Color(0xFF0866FF),
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Informasi Model Prediksi',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Model prediksi',
                    style: TextStyle(color: Color(0xFF75839A), fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.modelName,
                    key: const ValueKey('prediction-model'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Divider(height: 22),
                  const Text(
                    'Waktu prediksi dibuat',
                    style: TextStyle(color: Color(0xFF75839A), fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatWib(data.createdAt),
                    key: const ValueKey('prediction-created-at'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF4FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_done_outlined,
                color: Color(0xFF0866FF),
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Data dari API\n'
                  'Menampilkan hasil prediksi yang tersimpan di server. '
                  'Data pada server masih dapat berupa data pengujian.',
                  style: TextStyle(color: Color(0xFF405B80), fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tanggal target mengikuti hasil backend, '
          'tidak selalu untuk besok.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
        ),
        const SizedBox(height: 6),
        const Text(
          'Nilai ini merupakan prediksi produksi energi panel surya, '
          'bukan konsumsi pengguna atau kapasitas baterai.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
        ),
        const SizedBox(height: 6),
        const Text(
          'Model dijalankan oleh layanan AI. '
          'Aplikasi hanya menampilkan hasilnya.',
          style: TextStyle(color: Color(0xFF75839A), fontSize: 11),
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
}
