import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard Monitoring',
          key: const ValueKey('page-title'),
          style: textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
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
                  value: '5.00',
                  unit: 'V',
                  icon: Icons.bolt_outlined,
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Arus',
                  value: '0.20',
                  unit: 'A',
                  icon: Icons.electrical_services_outlined,
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Daya',
                  value: '1.00',
                  unit: 'W',
                  icon: Icons.solar_power_outlined,
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Energi harian',
                  value: '0.75',
                  unit: 'Wh',
                  icon: Icons.energy_savings_leaf_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Waktu pembacaan contoh'),
                      SizedBox(height: 4),
                      Text('01 November 2026, 12:00 WIB'),
                      SizedBox(height: 8),
                      Text('Belum terhubung ke API.'),
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
