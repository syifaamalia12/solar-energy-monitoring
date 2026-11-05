import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_config.dart';
import 'screens/main_screen.dart';
import 'services/api_dashboard_service.dart';
import 'services/dashboard_service.dart';
import 'services/history_report_service.dart';
import 'services/history_service.dart';
import 'services/monitoring_service.dart';
import 'services/prediction_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    MyApp(
      dashboardService: ApiDashboardService(
        baseUrl: AppConfig.apiBaseUrl,
        deviceId: AppConfig.deviceId,
      ),
      historyService: ApiHistoryService(
        baseUrl: AppConfig.apiBaseUrl,
        deviceId: AppConfig.deviceId,
      ),
      predictionService: ApiPredictionService(
        baseUrl: AppConfig.apiBaseUrl,
        deviceId: AppConfig.deviceId,
      ),
      monitoringService: ApiMonitoringService(
        baseUrl: AppConfig.apiBaseUrl,
        deviceId: AppConfig.deviceId,
      ),
      historyReportService: ApiHistoryReportService(
        baseUrl: AppConfig.apiBaseUrl,
        deviceId: AppConfig.deviceId,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MainScreen(
        dashboardService: dashboardService,
        historyService: historyService,
        predictionService: predictionService,
        monitoringService: monitoringService,
        historyReportService: historyReportService,
      ),
    );
  }
}
