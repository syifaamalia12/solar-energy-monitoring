
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from firebase_config import db

from schemas.monitoring import SensorReading

WIB = ZoneInfo("Asia/Jakarta")


def check_device(device_id: str):
    device = db.reference(f"devices/{device_id}").get()

    if device is None:
        raise HTTPException(
            status_code=404,
            detail="Perangkat tidak terdaftar"
        )


def get_date_range(start_date, end_date):
    start_time = datetime.combine(
        start_date, time.min, tzinfo=WIB
    )

    end_time = datetime.combine(
        end_date + timedelta(days=1),
        time.min,
        tzinfo=WIB
    )

    return start_time, end_time


def parse_timestamp(value):
    if isinstance(value, datetime):
        return value

    if isinstance(value, str):
        return datetime.fromisoformat(
            value.replace("Z", "+00:00")
        )

    raise ValueError("Format timestamp tidak valid")


def get_readings(device_id, start_time, end_time, limit=None):
    try:
        readings = db.reference("sensor_readings").get() or {}

        result = []

        for reading in readings.values():
            if not isinstance(reading, dict):
                continue

            if reading.get("device_id") != device_id:
                continue

            timestamp = parse_timestamp(reading["timestamp"])

            if start_time <= timestamp < end_time:
                result.append(reading)

        result.sort(
            key=lambda item: parse_timestamp(item["timestamp"])
        )

        if limit is not None:
            result = result[:limit]

        return result

    except HTTPException:
        raise
    except Exception as error:
        print(
            f"ERROR GET READINGS: {type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil data monitoring"
        )


def save_reading(data: SensorReading):
    try:
        check_device(data.device_id)

        power_w = round(
            data.voltage_v * data.current_a, 4
        )

        energy_wh = round(
            power_w * data.interval_seconds / 3600, 6
        )

        document_id = f"{data.device_id}_{data.reading_id}"

        payload = {
            "reading_id": data.reading_id,
            "device_id": data.device_id,
            "timestamp": data.timestamp.isoformat(),
            "voltage_v": data.voltage_v,
            "current_a": data.current_a,
            "interval_seconds": data.interval_seconds,
            "power_w": power_w,
            "energy_wh": energy_wh
        }

        reference = db.reference(
            f"sensor_readings/{document_id}"
        )

        outcome = {"status": None}

        def save_if_absent(current):
            if current is None:
                outcome["status"] = "saved"
                return payload

            if not isinstance(current, dict):
                outcome["status"] = "conflict"
                return current

            same_data = (
                current.get("reading_id") == data.reading_id
                and current.get("device_id") == data.device_id
                and parse_timestamp(
                    current["timestamp"]
                ) == data.timestamp
                and current.get("voltage_v") == data.voltage_v
                and current.get("current_a") == data.current_a
                and current.get("power_w") == power_w
                and current.get("energy_wh") == energy_wh
            )

            if "interval_seconds" in current:
                same_data = (
                    same_data
                    and current["interval_seconds"]
                    == data.interval_seconds
                )

            outcome["status"] = (
                "already_saved" if same_data else "conflict"
            )

            return current

        reference.transaction(save_if_absent)

        if outcome["status"] == "conflict":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Reading ID sudah digunakan "
                    "untuk data yang berbeda"
                )
            )

        return {
            "status": outcome["status"],
            "document_id": document_id,
            "power_w": power_w,
            "energy_wh": energy_wh
        }

    except HTTPException:
        raise
    except Exception as error:
        print(
            f"ERROR SIMPAN MONITORING: "
            f"{type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal menyimpan data ke Firebase"
        )


def get_latest(device_id: str):
    try:
        check_device(device_id)

        readings = db.reference(
            "sensor_readings"
        ).get() or {}

        matching = [
            reading
            for reading in readings.values()
            if isinstance(reading, dict)
            and reading.get("device_id") == device_id
        ]

        if not matching:
            raise HTTPException(
                status_code=404,
                detail="Belum ada data monitoring"
            )

        latest = max(
            matching,
            key=lambda item: parse_timestamp(item["timestamp"])
        )

        return {
            "status": "success",
            "data": latest
        }

    except HTTPException:
        raise
    except Exception as error:
        print(
            f"ERROR LATEST: {type(error).__name__}: {error}",
            flush=True
        )
        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil data monitoring"
        )
