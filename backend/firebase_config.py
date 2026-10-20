
import os
from pathlib import Path

import firebase_admin
from dotenv import load_dotenv
from firebase_admin import credentials, db

BASE_DIR = Path(__file__).resolve().parent

load_dotenv(BASE_DIR / ".env")

DATABASE_URL = os.getenv("FIREBASE_DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError(
        "FIREBASE_DATABASE_URL belum diatur di file .env"
    )

CREDENTIALS_PATH = (
    BASE_DIR / "credentials" / "firebase-service-account.json"
)

if not CREDENTIALS_PATH.exists():
    raise FileNotFoundError(
        f"Firebase credentials tidak ditemukan: {CREDENTIALS_PATH}"
    )

if not firebase_admin._apps:
    cred = credentials.Certificate(str(CREDENTIALS_PATH))

    firebase_admin.initialize_app(
        cred,
        {"databaseURL": DATABASE_URL}
    )
