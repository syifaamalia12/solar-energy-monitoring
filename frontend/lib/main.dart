import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/main_screen.dart';
import 'services/api_dashboard_service.dart';
import 'services/dashboard_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    MyApp(
      dashboardService: ApiDashboardService(
        baseUrl: AppConfig.apiBaseUrl,
        deviceId: AppConfig.deviceId,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.dashboardService});

  final DashboardService? dashboardService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MainScreen(dashboardService: dashboardService),
    );
  }
}
