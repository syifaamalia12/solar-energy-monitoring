
from math import isfinite

from pydantic import BaseModel, Field, field_validator


class DeviceReferenceCreate(BaseModel):
    device_name: str = Field(
        min_length=1,
        max_length=100
    )

    category: str = Field(
        min_length=1,
        max_length=50
    )

    power_w: float = Field(gt=0)

    @field_validator("power_w")
    @classmethod
    def validate_power(cls, value):
        if not isfinite(value):
            raise ValueError(
                "Daya perangkat harus berupa angka yang valid"
            )
        return value


class DeviceReferenceResponse(BaseModel):
    reference_id: str
    device_name: str
    category: str
    power_w: float
    created_at: str
