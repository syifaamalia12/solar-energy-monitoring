
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query

from security import verify_ai_api_key

from services.monitoring_service import (
    WIB,
    check_device,
    get_date_range,
    get_readings,
    parse_timestamp,
)


router = APIRouter(
    prefix="/api/v1/ai",
    tags=["AI Dataset"]
)


# ============================================================
# DATASET ENERGI HARIAN UNTUK LINEAR REGRESSION
# GET /api/v1/ai/dataset
#
# KEAMANAN: AI API KEY
# Digunakan oleh layanan AI untuk mengambil dataset.
# ============================================================

@router.get(
    "/dataset",
    dependencies=[Depends(verify_ai_api_key)]
)
def get_ai_dataset(
    device_id: str = Query(..., min_length=1),
    start_date: date = Query(...),
    end_date: date = Query(...)
):

    # ========================================================
    # 1. VALIDASI RENTANG TANGGAL
    # ========================================================

    if start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date tidak boleh melebihi end_date"
        )

    if (end_date - start_date).days > 30:
        raise HTTPException(
            status_code=400,
            detail="Rentang tanggal maksimal 31 hari"
        )

    try:

        # ====================================================
        # 2. PASTIKAN PERANGKAT TERDAFTAR
        # ====================================================

        check_device(device_id)

        # ====================================================
        # 3. TENTUKAN RENTANG WAKTU BERDASARKAN WIB
        # ====================================================

        start_time, end_time = get_date_range(
            start_date,
            end_date
        )

        # ====================================================
        # 4. AMBIL DATA DARI FIREBASE REALTIME DATABASE
        # ====================================================

        readings = get_readings(
            device_id,
            start_time,
            end_time
        )

        daily_energy = {}
        daily_count = {}

        # ====================================================
        # 5. KELOMPOKKAN PENGUKURAN BERDASARKAN TANGGAL WIB
        # ====================================================

        for reading in readings:

            timestamp_value = reading.get("timestamp")

            if timestamp_value is None:
                continue

            # Firebase Realtime Database menyimpan
            # timestamp dalam format string ISO 8601.
            timestamp = parse_timestamp(
                timestamp_value
            )

            # Konversi timestamp ke WIB.
            day = timestamp.astimezone(
                WIB
            ).date().isoformat()

            # Energi aktual dari hasil pengukuran.
            energy = float(
                reading.get("energy_wh", 0)
            )

            # Jumlahkan energi berdasarkan tanggal.
            daily_energy[day] = (
                daily_energy.get(day, 0) + energy
            )

            # Hitung jumlah pengukuran per tanggal.
            daily_count[day] = (
                daily_count.get(day, 0) + 1
            )

        # ====================================================
        # 6. SUSUN DATASET ENERGI HARIAN
        # ====================================================

        dataset = []

        for day in sorted(daily_energy):

            dataset.append({
                "date": day,
                "energy_wh": round(
                    daily_energy[day],
                    6
                ),
                "total_readings": daily_count[day]
            })

        # ====================================================
        # 7. KEMBALIKAN DATASET UNTUK TIM AI
        # ====================================================

        return {
            "status": "success",
            "device_id": device_id,
            "total_days_with_data": len(dataset),
            "ready_for_training": False,
            "data_source": "sensor_readings",
            "data": dataset
        }

    except HTTPException:
        raise

    except Exception as error:

        print(
            f"ERROR AI DATASET: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal menyiapkan dataset AI"
        )
