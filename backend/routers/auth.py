
from fastapi import APIRouter, Depends

from schemas.auth import (
    UserRegister,
    UserLogin,
    UserProfile,
    TokenResponse,
)

from services.auth_service import (
    register_user,
    login_user,
)

from security import get_current_user


router = APIRouter(
    prefix="/api/v1/auth",
    tags=["Authentication"]
)


# ============================================================
# 1. REGISTRASI PENGGUNA
# POST /api/v1/auth/register
# ============================================================

@router.post(
    "/register",
    status_code=201
)
def register(data: UserRegister):
    return register_user(
        username=data.username,
        password=data.password
    )


# ============================================================
# 2. LOGIN PENGGUNA
# POST /api/v1/auth/login
# ============================================================

@router.post(
    "/login",
    response_model=TokenResponse
)
def login(data: UserLogin):
    return login_user(
        username=data.username,
        password=data.password
    )


# ============================================================
# 3. PROFIL PENGGUNA
# GET /api/v1/auth/me
#
# KEAMANAN: JWT
# Mengembalikan user_id, username, dan role.
# ============================================================

@router.get(
    "/me",
    response_model=UserProfile
)
def get_profile(
    current_user: dict = Depends(get_current_user)
):
    return current_user
