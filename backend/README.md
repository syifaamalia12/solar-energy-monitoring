# Solar Energy Monitoring & Prediction — Backend

Backend prototipe menggunakan **Cloudflare Workers (JavaScript)** dan **Firebase Realtime Database**. Flutter membaca monitoring dan prediksi melalui API tanpa form Login/Register. Kredensial Firebase hanya digunakan di server.

## Struktur aktif

```text
backend/
├── src/
│   ├── index.js         # Routing, Firebase, monitoring, agregasi, dataset
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
npm run dev
```

Jika terminal sudah berada di `backend/`, lewati `cd backend`. Pengujian terakhir menggunakan Node.js 24. Gunakan URL lokal yang ditampilkan Wrangler.

## Konfigurasi

Sediakan variabel berikut melalui `.dev.vars` lokal yang diabaikan Git. Jangan memasukkan nilai secret ke source code, dokumentasi, log, atau Flutter.

| Variabel | Fungsi |
|---|---|
| `FIREBASE_DATABASE_URL` | URL Realtime Database |
| `FIREBASE_CLIENT_EMAIL` | Email service account untuk OAuth server |
| `FIREBASE_PRIVATE_KEY` | Private key service account; escape `\n` didukung |
| `IOT_API_KEY` | Kunci POST sensor |
| `AI_API_KEY` | Kunci dataset dan POST prediksi; wajib berbeda dari kunci IoT |
| `PUBLIC_DEVICE_IDS` | String JSON array daftar perangkat yang boleh dibaca publik |

Contoh konfigurasi perangkat publik tanpa secret:

```dotenv
PUBLIC_DEVICE_IDS='["solar-001","solar-002"]'
```

Jika belum diatur, default adalah `["solar-001"]`. Array kosong menolak seluruh pembacaan perangkat publik. Konfigurasi rusak menghasilkan 503. ID harus 1–120 karakter berupa huruf ASCII, angka, underscore, atau tanda minus. Pencocokan membedakan huruf besar/kecil; ID tidak valid menghasilkan 422 dan ID di luar daftar 404.

Daftar tersebut membatasi GET monitoring dan GET prediksi. Daftar ini tidak membuat perangkat baru dan tidak menggantikan autentikasi API IoT/AI. Firebase ID Token dan Web API key Firebase Authentication tidak diperlukan oleh prototipe saat ini.

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

Authentication, profil pengguna, Device Reference, dan Recommendations sudah dihapus dari backend aktif. Route lamanya mengembalikan 404; data Firebase lama tidak dihapus.

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

Perangkat harus sudah tersedia pada node `devices`. Energi wajib finite dan nonnegatif. `model_name` opsional, default `Linear Regression`. Body prediksi maksimal 4 KiB. Duplikat perangkat/tanggal menghasilkan 409.

Backend hanya menerima hasil prediksi energi aktual harian berikutnya dalam Wh dari layanan AI. Training dan eksekusi formula regresi belum diimplementasikan. Tanggal eksplisit mendukung pekerjaan AI yang terlambat atau backfill.

Respons POST: `{"status":"saved","data":{...}}`. Respons latest: `{"status":"success","data":{...}}`. Latest kosong menghasilkan 404. History kosong mengembalikan `data: []` dan `total_predictions: 0`.

## Struktur Firebase Realtime Database

```text
devices/{device_id}
sensor_readings/{device_id}/{tanggal_WIB}/{device_id}_{reading_id}
  reading_id, device_id, timestamp, voltage_v, current_a,
  power_w, energy_wh, interval_seconds
energy_predictions/{device_id}/{prediction_date}
  device_id, prediction_date, predicted_energy_wh, model_name, created_at
```

Worker mengakses database menggunakan OAuth service account. Publiknya API prototipe tidak berarti akses langsung Firebase dibuka. Database Rules tetap perlu melindungi akses klien langsung dan diverifikasi sebelum deployment. Node pengguna dan rekomendasi lama dibiarkan tanpa perubahan.

## Pengujian

```powershell
npm test
```

Hasil terakhir: **25 berhasil, 0 gagal**. Seluruh request eksternal dimock; pengujian tidak membaca `.dev.vars` atau mengakses Firebase produksi. Cakupan meliputi beberapa perangkat, daftar izin, isolasi data perangkat, API key IoT/AI, validasi, duplikasi, perhitungan energi, dan route yang dihapus.

Contoh pembacaan lokal tanpa token:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8787/api/v1/monitoring/latest?device_id=solar-002'
Invoke-RestMethod 'http://127.0.0.1:8787/api/v1/ai/predictions/latest?device_id=solar-002'
```

Sesuaikan port dengan output Wrangler. `wrangler dev` tetap dapat mengakses Firebase nyata sesuai `.dev.vars`; gunakan proyek Firebase pengujian untuk pengujian manual yang menulis data. Mock test belum membuktikan konfigurasi Rules atau integrasi perangkat dan Flutter.

## Deployment

Deployment masih ditunda. Sesudah integrasi diuji dan mendapat persetujuan:

```powershell
npm run deploy
```

Siapkan secret dan `PUBLIC_DEVICE_IDS` pada Worker remote. `.dev.vars` hanya konfigurasi lokal, bukan pengganti konfigurasi remote. Jangan membuka Database Rules untuk memberikan akses Flutter; Flutter menggunakan URL API Worker.
