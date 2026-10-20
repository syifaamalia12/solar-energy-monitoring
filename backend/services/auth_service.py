
import os
import re
import uuid

from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt

from dotenv import load_dotenv
from fastapi import HTTPException
from firebase_admin import db
from jwt.exceptions import InvalidTokenError
from pwdlib import PasswordHash


BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / ".env")

JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
JWT_ALGORITHM = "HS256"

JWT_EXPIRE_MINUTES = int(
    os.getenv("JWT_EXPIRE_MINUTES", "60")
)

if not JWT_SECRET_KEY or len(JWT_SECRET_KEY) < 32:
    raise RuntimeError(
        "JWT_SECRET_KEY harus diisi dengan kunci acak "
        "minimal 32 karakter di file .env"
    )

password_hash = PasswordHash.recommended()


# ============================================================
# 1. MEMBUAT HASH PASSWORD
# ============================================================

def hash_password(password: str):
    return password_hash.hash(password)


# ============================================================
# 2. MEMVERIFIKASI PASSWORD
# ============================================================

def verify_password(password: str, hashed_password: str):
    return password_hash.verify(
        password,
        hashed_password
    )


# ============================================================
# 3. MEMBUAT JWT ACCESS TOKEN
# ============================================================

def create_access_token(user_id: str):
    now = datetime.now(timezone.utc)

    expiration = now + timedelta(
        minutes=JWT_EXPIRE_MINUTES
    )

    payload = {
        "sub": user_id,
        "iat": now,
        "exp": expiration
    }

    return jwt.encode(
        payload,
        JWT_SECRET_KEY,
        algorithm=JWT_ALGORITHM
    )


# ============================================================
# 4. REGISTRASI PENGGUNA
# ============================================================

def register_user(username: str, password: str):
    username = username.strip().lower()

    if not re.fullmatch(r"[a-z0-9_]{3,30}", username):
        raise HTTPException(
            status_code=422,
            detail="Format username tidak valid"
        )

    username_ref = db.reference(
        f"usernames/{username}"
    )

    user_id = str(uuid.uuid4())

    def reserve_username(current):
        if current is not None:
            return current

        return user_id

    try:
        reserved_id = username_ref.transaction(
            reserve_username
        )

        if reserved_id != user_id:
            raise HTTPException(
                status_code=409,
                detail="Username sudah digunakan"
            )

        user_ref = db.reference(
            f"users/{user_id}"
        )

        user_data = {
            "user_id": user_id,
            "username": username,
            "password_hash": hash_password(password),
            "role": "user",
            "created_at": datetime.now(
                timezone.utc
            ).isoformat()
        }

        try:
            user_ref.set(user_data)

        except Exception:
            def release(current):
                return (
                    None
                    if current == user_id
                    else current
                )

            username_ref.transaction(release)
            raise

        return {
            "status": "success",
            "message": "Registrasi berhasil",
            "user_id": user_id,
            "username": username
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR REGISTER: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal mendaftarkan pengguna"
        )


# ============================================================
# 5. LOGIN PENGGUNA
# ============================================================

def login_user(username: str, password: str):
    try:
        username = username.strip().lower()

        user_id = db.reference(
            f"usernames/{username}"
        ).get()

        user = None

        if user_id:
            user = db.reference(
                f"users/{user_id}"
            ).get()

        if (
            not isinstance(user, dict)
            or not verify_password(
                password,
                user.get("password_hash", "")
            )
        ):
            raise HTTPException(
                status_code=401,
                detail="Username atau password salah"
            )

        token = create_access_token(
            user["user_id"]
        )

        return {
            "access_token": token,
            "token_type": "bearer"
        }

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR LOGIN: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal melakukan login"
        )


# ============================================================
# 6. MENGAMBIL PROFIL DARI JWT
# ============================================================

def get_user_from_token(token: str):
    try:
        payload = jwt.decode(
            token,
            JWT_SECRET_KEY,
            algorithms=[JWT_ALGORITHM]
        )

        user_id = payload.get("sub")

        if not isinstance(user_id, str) or not user_id:
            raise HTTPException(
                status_code=401,
                detail="Token tidak valid"
            )

        user = db.reference(
            f"users/{user_id}"
        ).get()

        if not isinstance(user, dict):
            raise HTTPException(
                status_code=401,
                detail="Pengguna tidak ditemukan"
            )

        return {
            "user_id": user["user_id"],
            "username": user["username"],
            "role": user.get("role", "user")
        }

    except InvalidTokenError:
        raise HTTPException(
            status_code=401,
            detail="Token tidak valid atau kedaluwarsa"
        )

    except HTTPException:
        raise

    except Exception as error:
        print(
            f"ERROR PROFIL: "
            f"{type(error).__name__}: {error}",
            flush=True
        )

        raise HTTPException(
            status_code=503,
            detail="Gagal mengambil profil pengguna"
        )
