import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../services/history_report_service.dart';
import '../services/history_service.dart';
import '../services/monitoring_service.dart';
import '../services/prediction_service.dart';
import 'dashboard_screen.dart';
import 'history_report_screen.dart';
import 'history_screen.dart';
import 'monitoring_screen.dart';
import 'prediction_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.dashboardService,
    this.historyService,
    this.predictionService,
    this.monitoringService,
    this.historyReportService,
  });

  final DashboardService? dashboardService;
  final HistoryService? historyService;
  final PredictionService? predictionService;
  final MonitoringService? monitoringService;
  final HistoryReportService? historyReportService;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _titles = [
    'SolarMonitor',
    'Monitoring',
    'Prediksi Energi',
    'Riwayat Energi',
    'Pengaturan',
  ];

  String get _pageTitle {
    if (_selectedIndex == 3 && widget.historyReportService != null) {
      return 'Riwayat Data';
    }

    return _titles[_selectedIndex];
  }

  void _selectPage(int index) {
    if (index == _selectedIndex) return;

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) {
          _selectPage(0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: _selectedIndex == 0 ? 68 : 56,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pageTitle,
                key: _selectedIndex == 0 ? null : const ValueKey('page-title'),
              ),
              if (_selectedIndex == 0) ...[
                const SizedBox(height: 3),
                const Text(
                  'Dashboard Monitoring',
                  key: ValueKey('page-title'),
                  style: TextStyle(
                    color: Color(0xFFDCEAFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            key: ValueKey('page-scroll-$_selectedIndex'),
            padding: EdgeInsets.zero,
            children: [
              if (_selectedIndex == 0) const _SolarHeaderImage(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                child: _buildSelectedPage(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE7EDF5))),
          ),
          child: NavigationBar(
            height: 68,
            selectedIndex: _selectedIndex,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: _selectPage,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Beranda',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'Monitoring',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Prediksi',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'Riwayat',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Pengaturan',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return DashboardScreen(
          service: widget.dashboardService,
          predictionService: widget.predictionService,
          onOpenPrediction: () => _selectPage(2),
        );
      case 1:
        return MonitoringScreen(
          dashboardService: widget.dashboardService,
          service: widget.monitoringService,
        );
      case 2:
        return PredictionScreen(service: widget.predictionService);
      case 3:
        final reportService = widget.historyReportService;

        if (reportService != null) {
          return HistoryReportScreen(service: reportService);
        }

        // Kompatibilitas sementara untuk pemanggil dan tes layanan lama.
        return HistoryScreen(service: widget.historyService);
      default:
        return const SettingsScreen();
    }
  }
}

class _SolarHeaderImage extends StatelessWidget {
  const _SolarHeaderImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/solar_panel.png',
      width: double.infinity,
      height: 130,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      cacheWidth: 1200,
      semanticLabel: 'Ilustrasi panel surya',
    );
  }
}
