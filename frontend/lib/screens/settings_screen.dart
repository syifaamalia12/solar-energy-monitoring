import 'package:flutter/material.dart';

import '../config/app_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _section(
          icon: Icons.solar_power,
          color: const Color(0xFF0866FF),
          title: 'Perangkat Prototipe',
          subtitle: AppConfig.deviceId,
          children: const [
            Text('ID perangkat: ${AppConfig.deviceId}'),
            SizedBox(height: 6),
            Text(
              'Status koneksi perangkat tidak disimpulkan dari '
              'halaman Pengaturan. Periksa waktu pembacaan di Monitoring.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _section(
          icon: Icons.devices_outlined,
          color: const Color(0xFF14A75B),
          title: 'Informasi Perangkat',
          subtitle: 'Lihat konfigurasi pembacaan',
          children: const [
            Text('Sensor: INA219'),
            SizedBox(height: 6),
            Text('Mikrokontroler: ESP8266'),
            SizedBox(height: 6),
            Text('Zona waktu tampilan: WIB'),
            SizedBox(height: 6),
            Text('Interval pembaruan aplikasi: 60 detik'),
            SizedBox(height: 6),
            Text(
              'Konfigurasi ini bukan hasil pemeriksaan langsung '
              'terhadap perangkat keras.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              Icons.notifications_outlined,
              color: Color(0xFFE5A000),
            ),
            title: Text(
              'Notifikasi',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Belum tersedia pada prototipe ini.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _section(
          icon: Icons.info_outline,
          color: const Color(0xFF0866FF),
          title: 'Tentang Aplikasi',
          subtitle: AppConfig.appName,
          children: [
            const Text(
              'Aplikasi pemantauan dan prediksi energi panel surya '
              'untuk prototipe satu perangkat, tanpa login.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Flutter membaca data melalui Cloudflare Workers. '
              'Aplikasi tidak mengakses database secara langsung.',
            ),
            const SizedBox(height: 8),
            const Text('Alamat backend:'),
            const SizedBox(height: 4),
            SelectableText(AppConfig.apiBaseUrl),
            const SizedBox(height: 8),
            const Text(
              'Gambar panel pada Beranda merupakan ilustrasi AI, '
              'bukan foto perangkat prototipe.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _section(
          icon: Icons.help_outline,
          color: const Color(0xFF75839A),
          title: 'Bantuan',
          subtitle: 'Panduan penggunaan',
          children: const [
            Text('Beranda: ringkasan pengukuran dan energi harian.'),
            SizedBox(height: 8),
            Text(
              'Monitoring: pembacaan sensor, tabel, dan grafik energi interval.',
            ),
            SizedBox(height: 8),
            Text('Prediksi: hasil prediksi yang tersedia di backend.'),
            SizedBox(height: 8),
            Text(
              'Riwayat: pilih Harian, Mingguan, atau Bulanan. '
              'Ketuk tanggal untuk memilih periode, atau gunakan panah '
              'untuk berpindah periode. Semua tanggal menggunakan WIB.',
            ),
            SizedBox(height: 8),
            Text(
              'Pada Riwayat Harian, tekan Muat lebih banyak jika tersedia '
              'untuk melihat pembacaan berikutnya.',
            ),
            SizedBox(height: 8),
            Text(
              'Tanda -- berarti data belum tersedia, bukan selalu bernilai nol.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
