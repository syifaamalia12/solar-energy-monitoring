# Solar Energy Monitoring & Prediction — Backend

Backend prototipe menggunakan **Cloudflare Workers (JavaScript)** dan **Cloudflare D1 (SQL)**. Flutter membaca monitoring dan prediksi melalui API tanpa form Login/Register. Database diakses melalui binding `DB` di Worker; tidak ada URL database publik atau kredensial database yang dibagikan ke Flutter.

## Struktur aktif

```text
backend/
├── src/
│   ├── index.js         # Routing, monitoring, agregasi, dataset
│   ├── api.js           # Error, validasi JSON, daftar perangkat publik
│   └── predictions.js   # Penyimpanan dan pembacaan hasil prediksi
├── test/api.test.mjs    # Pengujian mock
├── package.json
└── wrangler.jsonc
```

Entry point adalah `src/index.js`. File Python dan virtual environment yang masih tersedia tidak dijalankan oleh Worker JavaScript. `../backend-legacy/` menyimpan FastAPI lama sebagai referensi.

## Menjalankan lokal

Dari root repository, dengan Node.js dan npm terpasang:

```powershell
cd backend
npm ci
npx wrangler d1 migrations apply DB --local
npm run dev
```

Jika terminal sudah berada di `backend/`, lewati `cd backend`. Pengujian terakhir menggunakan Node.js 24. Gunakan URL lokal yang ditampilkan Wrangler.

## Konfigurasi

Sediakan variabel berikut melalui `.dev.vars` lokal yang diabaikan Git. Jangan memasukkan nilai secret ke source code, dokumentasi, log, atau Flutter.

| Variabel | Fungsi |
|---|---|
| `IOT_API_KEY` | Kunci POST sensor |
| `AI_API_KEY` | Kunci dataset dan POST prediksi; wajib berbeda dari kunci IoT |
| `PUBLIC_DEVICE_IDS` | String JSON array daftar perangkat yang boleh dibaca publik |

Contoh konfigurasi perangkat publik tanpa secret:

```dotenv
PUBLIC_DEVICE_IDS='["solar-001","solar-002"]'
```

Jika belum diatur, default adalah `["solar-001"]`. Array kosong menolak seluruh pembacaan perangkat publik. Konfigurasi rusak menghasilkan 503. ID harus 1–120 karakter berupa huruf ASCII, angka, underscore, atau tanda minus. Pencocokan membedakan huruf besar/kecil; ID tidak valid menghasilkan 422 dan ID di luar daftar 404.

Daftar tersebut membatasi GET monitoring dan GET prediksi. Daftar ini tidak membuat perangkat baru dan tidak menggantikan autentikasi API IoT/AI. Konfigurasi `FIREBASE_*`, Firebase ID Token, dan Firebase SDK tidak digunakan lagi. Variabel Firebase pada `.dev.vars` lokal sudah dilepas; secret remote lama belum dihapus.

## Sepuluh endpoint aktif

Path relatif terhadap URL Worker. Endpoint terlindungi memakai header `x-api-key`.

| Metode | Path | Akses | Query |
|---|---|---|---|
| GET | `/health` | Publik | — |
| POST | `/api/v1/monitoring` | `IOT_API_KEY` | — |
| GET | `/api/v1/monitoring/latest` | Perangkat publik | `device_id` |
| GET | `/api/v1/monitoring/history` | Perangkat publik | `device_id`, `limit` default 100, maks. 1000 |
| GET | `/api/v1/monitoring/daily-summary` | Perangkat publik | `device_id`, `date` default hari ini WIB |
| GET | `/api/v1/monitoring/daily-history` | Perangkat publik | `device_id`, `days` default 30, maks. 30 |
| GET | `/api/v1/ai/dataset` | `AI_API_KEY` | `device_id`, `days` default 14, maks. 30 |
| POST | `/api/v1/ai/predictions` | `AI_API_KEY` | — |
| GET | `/api/v1/ai/predictions/latest` | Perangkat publik | `device_id` wajib |
| GET | `/api/v1/ai/predictions/history` | Perangkat publik | `device_id`, `start_date`, `end_date` wajib |

Tanggal memakai `YYYY-MM-DD`. Monitoring dan dataset memakai default `device_id=solar-001` jika tidak diberikan. Latest dan history sensor mencari data dalam 14 hari terakhir. History sensor diurutkan dari terbaru. Riwayat prediksi menggunakan rentang inklusif maksimal 31 hari, diurutkan dari tanggal paling awal. Prediksi terbaru ditentukan berdasarkan tanggal prediksi terbesar.

Authentication, profil pengguna, Device Reference, dan Recommendations sudah dihapus dari backend aktif. Route lamanya mengembalikan 404; data Firebase lama tidak dihapus atau diimpor otomatis.

## Data sensor

POST monitoring menerima JSON:

```json
{
  "reading_id": "solar-002-20261101-120000",
  "device_id": "solar-002",
  "timestamp": "2026-11-01T12:00:00+07:00",
  "voltage_v": 5,
  "current_a": 0.5,
  "interval_seconds": 60
}
```

Timestamp wajib memiliki timezone. Tegangan dan arus harus berupa angka finite nonnegatif. Interval berupa bilangan bulat 1–3600 detik; perangkat prototipe ditujukan mengambil dan mengirim data setiap **60 detik**.

```text
power_w   = voltage_v × current_a
energy_wh = power_w × interval_seconds / 3600
```

Daya dihitung dari tegangan dan arus. Energi merupakan energi satu interval, bukan counter kumulatif. Agregasi harian menjumlahkan energi berdasarkan tanggal **Asia/Jakarta (WIB)**.

Respons simpan berisi `status`, `document_id`, `power_w`, dan `energy_wh`. ID yang sudah tersimpan pada perangkat/tanggal yang sama menghasilkan 409 tanpa overwrite. Buffer offline dan retry pada mikrokontroler belum menjadi implementasi backend.

## Prediksi energi

POST prediksi menerima JSON:

```json
{
  "device_id": "solar-002",
  "prediction_date": "2026-11-02",
  "predicted_energy_wh": 125.75,
  "model_name": "Linear Regression"
}
```

Perangkat harus sudah tersedia pada tabel `devices`. Energi wajib finite dan nonnegatif. `model_name` opsional, default `Linear Regression`. Body prediksi maksimal 4 KiB. Duplikat perangkat/tanggal menghasilkan 409.

Backend hanya menerima hasil prediksi energi aktual harian berikutnya dalam Wh dari layanan AI. Training dan eksekusi formula regresi belum diimplementasikan. Tanggal eksplisit mendukung pekerjaan AI yang terlambat atau backfill.

Respons POST: `{"status":"saved","data":{...}}`. Respons latest: `{"status":"success","data":{...}}`. Latest kosong menghasilkan 404. History kosong mengembalikan `data: []` dan `total_predictions: 0`.

## Struktur Cloudflare D1

Binding Worker: `env.DB`. Migrasi: `migrations/0001_initial.sql`.

| Tabel | Isi dan kunci |
|---|---|
| `devices` | `device_id` primary key, `device_name`, `location`, `install_date` |
| `sensor_readings` | Field sensor yang sama, ditambah kolom internal `reading_date`, `document_id`, `timestamp_ms`; primary key perangkat/tanggal WIB/document ID |
| `energy_predictions` | `device_id`, `prediction_date`, `predicted_energy_wh`, `model_name`, `created_at`; primary key perangkat/tanggal |

Kolom internal SQL tidak ditambahkan ke respons JSON. Timestamp asli tetap disimpan;
`timestamp_ms` dipakai untuk pengurutan waktu yang konsisten meskipun offset berbeda.
Tanggal WIB tetap dihitung dengan `Asia/Jakarta` di Worker. Query memakai parameter
terikat dan indeks perangkat/tanggal. Prediksi memiliki foreign key ke `devices`.
Sensor tetap menerima perangkat yang belum diprovisikan, mengikuti kontrak sebelumnya.

Migrasi hanya membuat skema; tidak mengisi perangkat produksi. Contoh provisioning
perangkat **lokal** sebelum mencoba POST prediksi:

```powershell
npx wrangler d1 execute DB --local --command "INSERT INTO devices (device_id, device_name) VALUES ('solar-001', 'Panel prototipe') ON CONFLICT(device_id) DO NOTHING;"
```

Database lokal dibuat dalam `.wrangler/`, yang diabaikan Git. Smoke test pengerjaan
ini menambahkan data contoh hanya di D1 lokal. Akses database tidak diberikan langsung
ke Flutter. Firebase lama tetap dipertahankan; impor data historis membutuhkan tahap
export/validasi/import terpisah sebelum pergantian produksi.

## Pengujian

```powershell
npm test
```

Hasil terakhir: **20 berhasil, 0 gagal**. Adapter binding D1 menjalankan SQL dan migrasi sebenarnya pada SQLite in-memory melalui `node:sqlite` (Node.js 24); seluruh akses jaringan diblokir. Cakupan mencakup 10 endpoint, beberapa perangkat, batas tanggal WIB, daftar izin, isolasi data, API key IoT/AI, validasi, duplikasi, foreign key, serta route yang dihapus. Tidak membaca `.dev.vars` atau mengakses produksi.

Build lokal:

```powershell
npm run build
```

Build menjalankan Wrangler `--dry-run`, bukan deployment. Tipe binding dapat diperbarui dengan `npx wrangler types`.

Contoh pembacaan lokal tanpa token:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8787/api/v1/monitoring/latest?device_id=solar-002'
Invoke-RestMethod 'http://127.0.0.1:8787/api/v1/ai/predictions/latest?device_id=solar-002'
```

Sesuaikan port dengan output Wrangler. `wrangler dev` memakai D1 lokal; jangan memakai `--remote` untuk pengujian ini. Smoke test 10 endpoint pada Worker lokal dan migrasi D1 lokal sudah berhasil. Integrasi Flutter/ESP8266 dan D1 remote belum diuji.

## Pembuatan D1 remote dan deployment (belum dijalankan)

`database_id` di `wrangler.jsonc` masih `00000000-0000-0000-0000-000000000000`,
placeholder untuk pengembangan lokal, **bukan ID database remote yang sudah dibuat**.
Pembuatan remote memerlukan akun Cloudflare. Sesudah persetujuan, dari folder backend:

```powershell
npx wrangler login
npx wrangler d1 create solar-energy-monitoring
```

Salin `database_id` hasil perintah ke binding `DB` pada `wrangler.jsonc`.
Jangan mengganti binding `DB`. Sesudah ID benar dan migrasi remote disetujui:

```powershell
npx wrangler d1 migrations apply DB --remote
```

Provisioning perangkat serta impor histori dilakukan dengan SQL yang sudah ditinjau;
jangan menganggap tabel baru berisi data Firebase. Verifikasi jumlah record, tanggal
WIB, total energi, duplikasi, dan prediksi sebelum cutover. Pertahankan Firebase lama
untuk referensi/rollback; Worker baru tidak membaca Firebase sebagai fallback.

Siapkan `IOT_API_KEY`, `AI_API_KEY`, dan `PUBLIC_DEVICE_IDS` pada Worker remote.
Secret Firebase remote dapat dihapus secara terpisah setelah cutover disetujui;
pengerjaan ini tidak mengubah konfigurasi remote.

Setelah seluruh verifikasi dan persetujuan deployment:

```powershell
npm test
npm run build
npm run deploy
```

Dokumentasi: [D1 bindings](https://developers.cloudflare.com/d1/worker-api/prepared-statements/),
[migrasi](https://developers.cloudflare.com/d1/reference/migrations/),
[pembuatan database](https://developers.cloudflare.com/d1/get-started/).
