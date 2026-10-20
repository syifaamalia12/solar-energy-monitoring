
from datetime import date

from fastapi import APIRouter, Depends, Query

from schemas.recommendations import RecommendationCreate

from services.recommendation_service import (
    create_recommendations,
    get_recommendations,
)

from security import (
    verify_ai_api_key,
    get_current_user,
)


router = APIRouter(
    prefix="/api/v1/ai/recommendations",
    tags=["Energy Recommendations"]
)


# ============================================================
# 1. MEMBUAT DAN MENYIMPAN REKOMENDASI ENERGI
# POST /api/v1/ai/recommendations
#
# KEAMANAN: AI API KEY
# Digunakan oleh layanan AI untuk membuat dan
# menyimpan rekomendasi berdasarkan hasil prediksi.
# ============================================================

@router.post(
    "",
    status_code=201,
    dependencies=[Depends(verify_ai_api_key)]
)
def create_energy_recommendations(
    data: RecommendationCreate
):
    return create_recommendations(data)


# ============================================================
# 2. MENGAMBIL REKOMENDASI BERDASARKAN TANGGAL
# GET /api/v1/ai/recommendations
#
# KEAMANAN: JWT
# Pengguna harus login untuk melihat rekomendasi.
# ============================================================

@router.get(
    "",
    dependencies=[Depends(get_current_user)]
)
def get_energy_recommendations(
    device_id: str = Query(..., min_length=1),
    prediction_date: date = Query(...)
):
    return get_recommendations(
        device_id,
        prediction_date
    )
