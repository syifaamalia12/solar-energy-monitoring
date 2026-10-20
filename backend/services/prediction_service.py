
from datetime import datetime, timezone, date

from fastapi import HTTPException
from firebase_admin import db

from schemas.predictions import EnergyPredictionCreate
from services.monitoring_service import check_device


# ============================================================
# 1. SIMPAN HASIL PREDIKSI ENERGI
# ============================================================

def save_prediction(data: EnergyPredictionCreate):
    try:
        # Pastikan perangkat terdaftar
        check_device(data.device_id)

        # Tanggal prediksi digunakan sebagai ID data
        prediction_date = data.prediction_date.isoformat()

        prediction_ref = db.reference(
            f"energy_predictions/{data.device_id}/{prediction_date}"
        )

        # Buat data yang akan disimpan
        payload = {
            "device_id": data.device_id,
            "prediction_date": prediction_date,
            "predicted_energy_wh": data.predicted_energy_wh,
            "model_name": data.model_name,
            "created_at": datetime.now(
                timezone.utc
            ).isoformat()
        }

        # Simpan ke Firebase Realtime Database
        # Transaksi mencegah prediksi lama tertimpa
        # apabila tanggal tersebut sudah memiliki data.
        def create_if_missing(current):
            if current is not None:
                return current
            return payload

        result = prediction_ref.transaction(create_if_missing)

        if result != payload:
            raise HTTPException(
                status_code=409,
                detail="Prediksi untuk tanggal ini sudah tersedia"
            )

        return {
            "status": "saved",
            "data": payload
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR SIMPAN PREDIKSI: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal menyimpan hasil prediksi"
        )


# ============================================================
# 2. AMBIL PREDIKSI TERBARU
# ============================================================

def get_latest_prediction(device_id: str):
    try:
        check_device(device_id)

        predictions = db.reference(
            f"energy_predictions/{device_id}"
        ).get()

        if not isinstance(predictions, dict) or not predictions:
            raise HTTPException(
                status_code=404,
                detail="Belum ada hasil prediksi"
            )

        # Kunci tanggal ISO YYYY-MM-DD dapat diurutkan
        latest_date = max(predictions.keys())
        latest = predictions[latest_date]

        return {
            "status": "success",
            "data": latest
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR PREDIKSI TERBARU: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil prediksi terbaru"
        )


# ============================================================
# 3. AMBIL RIWAYAT PREDIKSI
# ============================================================

def get_prediction_history(
    device_id: str,
    start_date: date,
    end_date: date
):
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
        check_device(device_id)

        # Query berdasarkan tanggal pada key Firebase
        predictions = db.reference(
            f"energy_predictions/{device_id}"
        ).order_by_key().start_at(
            start_date.isoformat()
        ).end_at(
            end_date.isoformat()
        ).get()

        if not isinstance(predictions, dict):
            predictions = {}

        history = [
            predictions[key]
            for key in sorted(predictions.keys())
        ]

        return {
            "status": "success",
            "device_id": device_id,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "total_predictions": len(history),
            "data": history
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR RIWAYAT PREDIKSI: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil riwayat prediksi"
        )
