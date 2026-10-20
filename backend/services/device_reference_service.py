
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException
from firebase_admin import db

from schemas.device_reference import DeviceReferenceCreate


# ============================================================
# 1. MENAMBAHKAN REFERENSI PERANGKAT
# ============================================================

def create_device_reference(data: DeviceReferenceCreate):
    try:
        reference_id = str(uuid4())

        payload = {
            "reference_id": reference_id,
            "device_name": data.device_name,
            "category": data.category,
            "power_w": data.power_w,
            "created_at": datetime.now(
                timezone.utc
            ).isoformat()
        }

        db.reference(
            f"device_reference/{reference_id}"
        ).set(payload)

        return {
            "status": "saved",
            "data": payload
        }

    except Exception as error:
        print(
            f"ERROR CREATE DEVICE REFERENCE: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal menyimpan referensi perangkat"
        )


# ============================================================
# 2. MENGAMBIL SELURUH REFERENSI PERANGKAT
# ============================================================

def get_all_device_references():
    try:
        records = db.reference(
            "device_reference"
        ).get()

        if not isinstance(records, dict):
            records = {}

        devices = sorted(
            records.values(),
            key=lambda item: item.get("device_name", "").lower()
        )

        return {
            "status": "success",
            "total_devices": len(devices),
            "data": devices
        }

    except Exception as error:
        print(
            f"ERROR GET DEVICE REFERENCES: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil referensi perangkat"
        )


# ============================================================
# 3. MENGAMBIL DETAIL REFERENSI PERANGKAT
# ============================================================

def get_device_reference(reference_id: str):
    try:
        record = db.reference(
            f"device_reference/{reference_id}"
        ).get()

        if not isinstance(record, dict):
            raise HTTPException(
                status_code=404,
                detail="Referensi perangkat tidak ditemukan"
            )

        return {
            "status": "success",
            "data": record
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR GET DEVICE REFERENCE: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil detail referensi perangkat"
        )
