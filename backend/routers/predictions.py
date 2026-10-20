
from datetime import date

from fastapi import APIRouter, Depends, Query

from schemas.predictions import EnergyPredictionCreate

from security import (
    verify_ai_api_key,
    get_current_user,
)

from services.prediction_service import (
    save_prediction,
    get_latest_prediction,
    get_prediction_history,
)


router = APIRouter(
    prefix="/api/v1/ai/predictions",
    tags=["Energy Predictions"]
)


# ============================================================
# 1. SIMPAN HASIL PREDIKSI ENERGI
# POST /api/v1/ai/predictions
#
# KEAMANAN: AI API KEY
# Digunakan oleh layanan AI untuk menyimpan hasil prediksi.
# ============================================================

@router.post(
    "",
    status_code=201,
    dependencies=[Depends(verify_ai_api_key)]
)
def create_prediction(
    data: EnergyPredictionCreate
):
    return save_prediction(data)


# ============================================================
# 2. AMBIL PREDIKSI TERBARU
# GET /api/v1/ai/predictions/latest
#
# KEAMANAN: JWT
# Pengguna harus login untuk melihat hasil prediksi.
# ============================================================

@router.get(
    "/latest",
    dependencies=[Depends(get_current_user)]
)
def latest_prediction(
    device_id: str = Query(..., min_length=1)
):
    return get_latest_prediction(device_id)


# ============================================================
# 3. AMBIL RIWAYAT PREDIKSI
# GET /api/v1/ai/predictions/history
#
# KEAMANAN: JWT
# Pengguna harus login untuk melihat riwayat prediksi.
# ============================================================

@router.get(
    "/history",
    dependencies=[Depends(get_current_user)]
)
def prediction_history(
    device_id: str = Query(..., min_length=1),
    start_date: date = Query(...),
    end_date: date = Query(...)
):
    return get_prediction_history(
        device_id,
        start_date,
        end_date
    )
