import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/dashboard_service.dart';
import '../services/history_service.dart';
import '../services/prediction_service.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'prediction_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.dashboardService,
    this.historyService,
    this.predictionService,
  });

  final DashboardService? dashboardService;
  final HistoryService? historyService;
  final PredictionService? predictionService;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _titles = [
    'Dashboard Monitoring',
    'Riwayat Energi',
    'Prediksi Energi',
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_titles[_selectedIndex])),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                AppConfig.appName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Perangkat: ${AppConfig.deviceId}'),
              const SizedBox(height: 24),
              if (_selectedIndex == 0)
                DashboardScreen(service: widget.dashboardService)
              else if (_selectedIndex == 1)
                HistoryScreen(service: widget.historyService)
              else
                PredictionScreen(service: widget.predictionService),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Riwayat',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Prediksi',
            ),
          ],
        ),
      ),
    );
  }
}
