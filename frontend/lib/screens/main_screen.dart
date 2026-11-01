import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/dashboard_service.dart';
import 'dashboard_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.dashboardService});

  final DashboardService? dashboardService;

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

  static const _icons = [
    Icons.solar_power_outlined,
    Icons.bar_chart_outlined,
    Icons.insights_outlined,
  ];

  static const _messages = [
    'Tegangan, arus, daya, dan energi harian akan ditampilkan di sini.',
    'Riwayat dan grafik energi harian akan ditampilkan di sini.',
    'Hasil prediksi produksi energi akan ditampilkan di sini.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          _icons[_selectedIndex],
                          size: 64,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _titles[_selectedIndex],
                          key: const ValueKey('page-title'),
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _messages[_selectedIndex],
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Kerangka tampilan - belum terhubung ke API.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
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
