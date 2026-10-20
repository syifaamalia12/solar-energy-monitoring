
from datetime import datetime
from zoneinfo import ZoneInfo

from firebase_config import db

WIB = ZoneInfo("Asia/Jakarta")

device_id = "solar-001"

device_ref = db.reference(f"devices/{device_id}")

if device_ref.get() is None:
    device_ref.set({
        "device_id": device_id,
        "device_name": "NodeMCU ESP8266 Panel Surya 1",
        "location": "Lokasi Pengujian",
        "install_date": datetime.now(WIB).isoformat()
    })

    print("BERHASIL membuat perangkat solar-001")
else:
    print("Perangkat solar-001 sudah terdaftar")

print("Data perangkat:", device_ref.get())
