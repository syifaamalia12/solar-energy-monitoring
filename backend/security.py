
import os
import secrets

from pathlib import Path

from dotenv import load_dotenv

from fastapi import (
    Depends,
    Header,
    HTTPException,
)

from fastapi.security import (
    HTTPAuthorizationCredentials,
    HTTPBearer,
)

from services.auth_service import get_user_from_token


# ============================================================
# 1. LOAD ENVIRONMENT VARIABLES
# ============================================================

load_dotenv(
    Path(__file__).resolve().parent / ".env"
)

IOT_API_KEY = os.getenv("IOT_API_KEY")
AI_API_KEY = os.getenv("AI_API_KEY")


if not IOT_API_KEY:
    raise RuntimeError(
        "IOT_API_KEY belum diatur pada file .env"
    )

if not AI_API_KEY:
    raise RuntimeError(
        "AI_API_KEY belum diatur pada file .env"
    )

if secrets.compare_digest(
    IOT_API_KEY,
    AI_API_KEY
):
    raise RuntimeError(
        "IOT_API_KEY dan AI_API_KEY harus berbeda"
    )


# ============================================================
# 2. IOT API KEY AUTHENTICATION
# ============================================================

def verify_iot_api_key(
    x_api_key: str | None = Header(default=None)
):
    if (
        not x_api_key
        or not secrets.compare_digest(
            x_api_key,
            IOT_API_KEY
        )
    ):
        raise HTTPException(
            status_code=401,
            detail="API Key tidak valid atau tidak diberikan"
        )


# ============================================================
# 3. AI API KEY AUTHENTICATION
# ============================================================

def verify_ai_api_key(
    x_api_key: str | None = Header(default=None)
):
    if (
        not x_api_key
        or not secrets.compare_digest(
            x_api_key,
            AI_API_KEY
        )
    ):
        raise HTTPException(
            status_code=401,
            detail="API Key tidak valid atau tidak diberikan"
        )


# ============================================================
# 4. JWT AUTHENTICATION DEPENDENCY
# ============================================================

bearer_scheme = HTTPBearer(
    auto_error=False
)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(
        bearer_scheme
    )
):
    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="Token autentikasi tidak diberikan",
            headers={
                "WWW-Authenticate": "Bearer"
            }
        )

    return get_user_from_token(
        credentials.credentials
    )


# ============================================================
# 5. ADMIN AUTHORIZATION DEPENDENCY
# ============================================================

def require_admin(
    current_user: dict = Depends(get_current_user)
):
    if current_user.get("role") != "admin":
        raise HTTPException(
            status_code=403,
            detail="Akses hanya diizinkan untuk administrator"
        )

    return current_user
