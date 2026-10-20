
from firebase_config import db

try:
    ref = db.reference("/")

    data = ref.get()

    print("BERHASIL terhubung ke Firebase Realtime Database")
    print("Data database:", data)

except Exception as error:
    print("GAGAL terhubung ke Firebase Realtime Database")
    print(f"Error: {type(error).__name__}: {error}")
