
from datetime import datetime, timezone
from fastapi import HTTPException
from firebase_admin import db

from schemas.recommendations import RecommendationCreate
from services.monitoring_service import check_device


# ============================================================
# 1. MEMBUAT DAN MENYIMPAN REKOMENDASI
# ============================================================

def create_recommendations(data: RecommendationCreate):
    try:
        # Pastikan perangkat monitoring terdaftar
        check_device(data.device_id)

        prediction_date = data.prediction_date.isoformat()

        # Ambil hasil prediksi Linear Regression
        prediction = db.reference(
            f"energy_predictions/{data.device_id}/{prediction_date}"
        ).get()

        if not isinstance(prediction, dict):
            raise HTTPException(
                status_code=404,
                detail="Prediksi energi untuk tanggal tersebut belum tersedia"
            )

        predicted_energy_wh = prediction.get(
            "predicted_energy_wh"
        )

        if predicted_energy_wh is None:
            raise HTTPException(
                status_code=422,
                detail="Nilai prediksi energi tidak tersedia"
            )

        # Ambil daftar referensi perangkat listrik
        references = db.reference(
            "device_reference"
        ).get()

        if not isinstance(references, dict) or not references:
            raise HTTPException(
                status_code=404,
                detail="Belum ada referensi perangkat listrik"
            )

        recommendations = []

        # Hitung estimasi durasi setiap perangkat
        for reference_id, device in references.items():
            if not isinstance(device, dict):
                continue

            power_w = device.get("power_w")

            if (
                not isinstance(power_w, (int, float))
                or isinstance(power_w, bool)
                or power_w <= 0
            ):
                continue

            estimated_hours = (
                predicted_energy_wh / power_w
            )

            recommendations.append({
                "reference_id": reference_id,
                "device_name": device.get("device_name", ""),
                "category": device.get("category", ""),
                "power_w": power_w,
                "estimated_duration_hours": round(
                    estimated_hours, 2
                )
            })

        if not recommendations:
            raise HTTPException(
                status_code=422,
                detail="Tidak ada referensi perangkat dengan daya valid"
            )

        # Urutkan berdasarkan durasi penggunaan terlama
        recommendations.sort(
            key=lambda item: item["estimated_duration_hours"],
            reverse=True
        )

        payload = {
            "device_id": data.device_id,
            "prediction_date": prediction_date,
            "predicted_energy_wh": predicted_energy_wh,
            "recommendations": recommendations,
            "created_at": datetime.now(
                timezone.utc
            ).isoformat()
        }

        # Simpan berdasarkan perangkat dan tanggal prediksi
        db.reference(
            f"recommendations/{data.device_id}/{prediction_date}"
        ).set(payload)

        return {
            "status": "saved",
            "data": payload
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR CREATE RECOMMENDATIONS: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal membuat rekomendasi energi"
        )


# ============================================================
# 2. MENGAMBIL REKOMENDASI BERDASARKAN TANGGAL
# ============================================================

def get_recommendations(device_id: str, prediction_date):
    try:
        check_device(device_id)

        date_key = prediction_date.isoformat()

        recommendation = db.reference(
            f"recommendations/{device_id}/{date_key}"
        ).get()

        if not isinstance(recommendation, dict):
            raise HTTPException(
                status_code=404,
                detail="Rekomendasi energi belum tersedia"
            )

        return {
            "status": "success",
            "data": recommendation
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR GET RECOMMENDATIONS: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil rekomendasi energi"
        )
