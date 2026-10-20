
from datetime import date

from pydantic import BaseModel, Field


class RecommendationCreate(BaseModel):
    device_id: str = Field(min_length=1)
    prediction_date: date


class RecommendationItem(BaseModel):
    reference_id: str
    device_name: str
    category: str
    power_w: float = Field(gt=0)
    estimated_duration_hours: float = Field(ge=0)


class RecommendationResponse(BaseModel):
    device_id: str
    prediction_date: date
    predicted_energy_wh: float = Field(ge=0)
    recommendations: list[RecommendationItem]
    created_at: str
