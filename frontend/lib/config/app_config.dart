class AppConfig {
  AppConfig._();

  static const String appName = 'Solar Energy Monitoring';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://solar-cloudflare-api.amaliasyifa657.workers.dev',
  );

  static const String deviceId = String.fromEnvironment(
    'DEVICE_ID',
    defaultValue: 'solar-001',
  );

  static const Duration refreshInterval = Duration(seconds: 60);
}
