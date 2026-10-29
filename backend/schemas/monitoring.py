
from datetime import datetime
from math import isfinite

from pydantic import BaseModel, Field, field_validator


class SensorReading(BaseModel):
    reading_id: str = Field(min_length=1)
    device_id: str = Field(min_length=1)
    timestamp: datetime

    voltage_v: float = Field(ge=0)
    current_a: float = Field(ge=0)
    interval_seconds: float = Field(
        gt=0,
        le=3600,
        allow_inf_nan=False
    )

    @field_validator("voltage_v", "current_a")
    @classmethod
    def check_finite(cls, value):
        if not isfinite(value):
            raise ValueError("Nilai harus berupa angka yang valid")
        return value

    @field_validator("timestamp")
    @classmethod
    def check_timezone(cls, value):
        if value.tzinfo is None:
            raise ValueError("Timestamp harus memiliki timezone")
        return value
