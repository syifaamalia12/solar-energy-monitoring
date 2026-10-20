
from datetime import date
from math import isfinite

from pydantic import BaseModel, Field, field_validator


class EnergyPredictionCreate(BaseModel):
    device_id: str = Field(
        min_length=1
    )

    prediction_date: date

    predicted_energy_wh: float = Field(
        ge=0
    )

    model_name: str = Field(
        default="Linear Regression",
        min_length=1
    )

    @field_validator("predicted_energy_wh")
    @classmethod
    def validate_energy(cls, value):
        if not isfinite(value):
            raise ValueError(
                "Nilai prediksi harus berupa angka yang valid"
            )
        return value


class EnergyPredictionResponse(BaseModel):
    device_id: str
    prediction_date: date
    predicted_energy_wh: float
    model_name: str
    created_at: str
