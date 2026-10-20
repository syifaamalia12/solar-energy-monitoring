
from fastapi import APIRouter, Depends

from schemas.device_reference import DeviceReferenceCreate

from security import (
    get_current_user,
    require_admin,
)

from services.device_reference_service import (
    create_device_reference,
    get_all_device_references,
    get_device_reference,
)


router = APIRouter(
    prefix="/api/v1/device-reference",
    tags=["Device Reference"]
)


# ============================================================
# 1. MENAMBAHKAN REFERENSI PERANGKAT
# POST /api/v1/device-reference
#
# KEAMANAN: JWT + ADMIN ROLE
# ============================================================

@router.post(
    "",
    status_code=201,
    dependencies=[Depends(require_admin)]
)
def add_device_reference(
    data: DeviceReferenceCreate
):
    return create_device_reference(data)


# ============================================================
# 2. MENGAMBIL DAFTAR REFERENSI PERANGKAT
# GET /api/v1/device-reference
#
# KEAMANAN: JWT
# ============================================================

@router.get(
    "",
    dependencies=[Depends(get_current_user)]
)
def list_device_references():
    return get_all_device_references()


# ============================================================
# 3. MENGAMBIL DETAIL REFERENSI PERANGKAT
# GET /api/v1/device-reference/{reference_id}
#
# KEAMANAN: JWT
# ============================================================

@router.get(
    "/{reference_id}",
    dependencies=[Depends(get_current_user)]
)
def device_reference_detail(
    reference_id: str
):
    return get_device_reference(
        reference_id
    )
