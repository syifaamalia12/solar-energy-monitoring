
from datetime import date, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query

from schemas.monitoring import SensorReading

from security import (
    verify_iot_api_key,
    get_current_user,
)

from services.monitoring_service import (
    check_device,
    get_date_range,
    get_readings,
    save_reading,
    get_latest,
    parse_timestamp,
)


WIB = ZoneInfo("Asia/Jakarta")


router = APIRouter(
    prefix="/api/v1/monitoring",
    tags=["Monitoring"]
)


# ============================================================
# VALIDASI RENTANG TANGGAL
# ============================================================

def validate_dates(
    start_date: date,
    end_date: date,
    max_days=None
):
    if start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date tidak boleh melebihi end_date"
        )

    if max_days is not None:
        if (end_date - start_date).days >= max_days:
            raise HTTPException(
                status_code=400,
                detail=f"Rentang tanggal maksimal {max_days} hari"
            )


# ============================================================
# 1. SIMPAN DATA MONITORING
# POST /api/v1/monitoring
#
# KEAMANAN: API KEY
# Digunakan oleh ESP8266 untuk mengirim data sensor.
# ============================================================

@router.post(
    "",
    dependencies=[Depends(verify_iot_api_key)]
)
def save_monitoring(data: SensorReading):
    return save_reading(data)


# ============================================================
# 2. DATA MONITORING TERBARU
# GET /api/v1/monitoring/latest
#
# KEAMANAN: JWT
# ============================================================

@router.get(
    "/latest",
    dependencies=[Depends(get_current_user)]
)
def get_latest_monitoring(
    device_id: str = Query(..., min_length=1)
):
    return get_latest(device_id)


# ============================================================
# 3. HISTORI MONITORING
# GET /api/v1/monitoring/history
#
# KEAMANAN: JWT
# ============================================================

@router.get(
    "/history",
    dependencies=[Depends(get_current_user)]
)
def get_monitoring_history(
    device_id: str = Query(..., min_length=1),
    start_date: date = Query(...),
    end_date: date = Query(...),
    limit: int = Query(100, ge=1, le=1000)
):
    validate_dates(start_date, end_date)

    try:
        check_device(device_id)

        start_time, end_time = get_date_range(
            start_date,
            end_date
        )

        readings = get_readings(
            device_id,
            start_time,
            end_time,
            limit
        )

        return {
            "status": "success",
            "device_id": device_id,
            "start_date": str(start_date),
            "end_date": str(end_date),
            "total_returned": len(readings),
            "data": readings
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR HISTORI: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil histori monitoring"
        )


# ============================================================
# 4. REKAP ENERGI HARIAN
# GET /api/v1/monitoring/daily-summary
#
# KEAMANAN: JWT
# ============================================================

@router.get(
    "/daily-summary",
    dependencies=[Depends(get_current_user)]
)
def get_daily_summary(
    device_id: str = Query(..., min_length=1),
    target_date: date = Query(...)
):
    try:
        check_device(device_id)

        start_time, end_time = get_date_range(
            target_date,
            target_date
        )

        readings = get_readings(
            device_id,
            start_time,
            end_time
        )

        total_energy = round(
            sum(
                float(item.get("energy_wh", 0))
                for item in readings
            ),
            6
        )

        return {
            "status": "success",
            "device_id": device_id,
            "date": str(target_date),
            "total_readings": len(readings),
            "total_energy_wh": total_energy
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR DAILY SUMMARY: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal menghitung rekap energi harian"
        )


# ============================================================
# 5. HISTORI ENERGI HARIAN
# GET /api/v1/monitoring/daily-history
#
# KEAMANAN: JWT
# ============================================================

@router.get(
    "/daily-history",
    dependencies=[Depends(get_current_user)]
)
def get_daily_history(
    device_id: str = Query(..., min_length=1),
    start_date: date = Query(...),
    end_date: date = Query(...)
):
    validate_dates(
        start_date,
        end_date,
        max_days=31
    )

    try:
        check_device(device_id)

        start_time, end_time = get_date_range(
            start_date,
            end_date
        )

        readings = get_readings(
            device_id,
            start_time,
            end_time
        )

        daily_totals = {}
        daily_counts = {}

        for reading in readings:
            timestamp_value = reading.get("timestamp")

            if timestamp_value is None:
                continue

            # Firebase Realtime Database menyimpan
            # timestamp sebagai string ISO 8601.
            timestamp = parse_timestamp(
                timestamp_value
            )

            # Konversi ke WIB sebelum menentukan tanggal.
            day = timestamp.astimezone(
                WIB
            ).date().isoformat()

            energy = float(
                reading.get("energy_wh", 0)
            )

            daily_totals[day] = (
                daily_totals.get(day, 0) + energy
            )

            daily_counts[day] = (
                daily_counts.get(day, 0) + 1
            )

        results = []
        current_date = start_date

        while current_date <= end_date:
            day = current_date.isoformat()

            count = daily_counts.get(day, 0)

            results.append({
                "date": day,
                "total_energy_wh": (
                    round(daily_totals[day], 6)
                    if count > 0
                    else None
                ),
                "total_readings": count,
                "has_data": count > 0
            })

            current_date += timedelta(days=1)

        return {
            "status": "success",
            "device_id": device_id,
            "start_date": str(start_date),
            "end_date": str(end_date),
            "total_days": len(results),
            "data": results
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR DAILY HISTORY: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil rekap energi harian"
        )
