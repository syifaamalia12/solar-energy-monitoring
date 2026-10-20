
from fastapi import FastAPI

from routers.monitoring import router as monitoring_router
from routers.dataset import router as dataset_router
from routers.auth import router as auth_router
from routers.predictions import router as predictions_router
from routers.device_reference import router as device_reference_router

from routers.recommendations import router as recommendations_router

app = FastAPI(
    title="Solar Energy Monitoring API",
    version="1.0.0"
)


# ============================================================
# HEALTH CHECK
# ============================================================

@app.get("/health", tags=["Health"])
def health_check():
    return {
        "status": "ok",
        "message": "Backend berjalan dengan baik"
    }


# ============================================================
# ROUTER MONITORING
# ============================================================

app.include_router(monitoring_router)


# ============================================================
# ROUTER DATASET AI
# ============================================================

app.include_router(dataset_router)


# ============================================================
# ROUTER AUTHENTICATION
# ============================================================

app.include_router(auth_router)


# ============================================================
# ROUTER ENERGY PREDICTIONS
# ============================================================

app.include_router(predictions_router)


# ============================================================
# ROUTER DEVICE REFERENCE
# ============================================================

app.include_router(device_reference_router)


# ============================================================
# ROUTER ENERGY RECOMMENDATIONS
# ============================================================

app.include_router(recommendations_router)