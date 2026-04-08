# api.py
# Credora — FastAPI Scoring Endpoint
#
# Loads the trained GradientBoostingClassifier pipeline and exposes
# a single POST endpoint: /score
#
# The endpoint accepts a behavioral profile payload, validates it with
# Pydantic, runs it through the model, and returns a 0–1000 Credora score.
#
# Raw behavioral data is never logged or persisted — only the score is returned.

import hashlib
import os
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

load_dotenv()

# ── Constants ─────────────────────────────────────────────────────────────────

MODELS_DIR = Path(__file__).parent / "models"
MODEL_ENV  = os.getenv("CREDORA_MODEL_FILE")

FEATURES = [
    "days_between_payments_mean",
    "days_between_payments_std",
    "missed_payment_count",
    "monthly_transaction_count",
    "monthly_transaction_value",
    "remittance_frequency",
    "remittance_recency_days",
    "airtime_topup_frequency",
    "airtime_topup_avg_amount",
    "weekend_activity_ratio",
    "month_end_spike_ratio",
    "account_longevity_months",
]

# ── Load model ────────────────────────────────────────────────────────────────

def load_model():
    """
    Load the versioned model file.
    Reads the filename from the CREDORA_MODEL_FILE env variable.
    Logs the filename and SHA256 checksum on every startup so you
    always know exactly which model is running.
    """
    if not MODEL_ENV:
        raise RuntimeError(
            "CREDORA_MODEL_FILE environment variable is not set. "
            "Add it to your .env file, e.g.: "
            "CREDORA_MODEL_FILE=credora_model_v1_20260408.joblib"
        )

    model_path = MODELS_DIR / MODEL_ENV

    if not model_path.exists():
        raise FileNotFoundError(
            f"Model file not found: {model_path}. "
            "Run score_model.py first to train and save the model."
        )

    # Compute SHA256 checksum for integrity verification
    sha256 = hashlib.sha256(model_path.read_bytes()).hexdigest()
    print(f"[api] Loading model: {model_path.name}")
    print(f"[api] SHA256: {sha256}")

    pipeline = joblib.load(model_path)
    print("[api] Model loaded successfully.")
    return pipeline


pipeline = load_model()

# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Credora Scoring API",
    description="Behavioral credit scoring engine for the Credora protocol.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "*").split(","),
    allow_methods=["POST"],
    allow_headers=["Content-Type"],
)

# ── Pydantic input model ──────────────────────────────────────────────────────

class BehavioralProfile(BaseModel):
    """
    Input payload for the /score endpoint.
    Every field is validated for type and realistic range.
    Values outside these ranges are rejected before they reach the model.
    """
    days_between_payments_mean: float = Field(ge=1,    le=90)
    days_between_payments_std:  float = Field(ge=0,    le=30)
    missed_payment_count:       int   = Field(ge=0,    le=20)
    monthly_transaction_count:  float = Field(ge=0,    le=100)
    monthly_transaction_value:  float = Field(ge=0,    le=100000)
    remittance_frequency:       float = Field(ge=0,    le=10)
    remittance_recency_days:    float = Field(ge=0,    le=365)
    airtime_topup_frequency:    float = Field(ge=0,    le=20)
    airtime_topup_avg_amount:   float = Field(ge=0,    le=1000)
    weekend_activity_ratio:     float = Field(ge=0.0,  le=1.0)
    month_end_spike_ratio:      float = Field(ge=0.0,  le=5.0)
    account_longevity_months:   float = Field(ge=1,    le=120)

    @field_validator("days_between_payments_mean",
                     "days_between_payments_std",
                     "monthly_transaction_count",
                     "monthly_transaction_value",
                     "remittance_frequency",
                     "remittance_recency_days",
                     "airtime_topup_frequency",
                     "airtime_topup_avg_amount",
                     "weekend_activity_ratio",
                     "month_end_spike_ratio",
                     "account_longevity_months",
                     mode="before")
    @classmethod
    def allow_none(cls, v):
        """
        Allow None for fields that can be missing in real-world data.
        The pipeline's SimpleImputer will fill them with training medians.
        """
        return v


# ── Response model ────────────────────────────────────────────────────────────

class ScoreResponse(BaseModel):
    """
    Response payload returned by the /score endpoint.
    score:       0–1000 Credora creditworthiness score
    probability: raw default probability from the model (0.0–1.0)
    model:       filename of the model that produced this score
    """
    score:       int
    probability: float
    model:       str


# ── Scoring logic ─────────────────────────────────────────────────────────────

def compute_score(profile: BehavioralProfile) -> ScoreResponse:
    """
    Run the behavioral profile through the pipeline and return a score.

    How the score is calculated:
      1. The model returns a default probability (0.0 = safe, 1.0 = will default)
      2. We invert it: creditworthiness = 1 - default_probability
      3. We scale to 0–1000: score = int(creditworthiness * 1000)

    A score of 1000 means the model is maximally confident the user will not default.
    A score of 0 means the model is maximally confident they will default.
    """
    # Build a single-row DataFrame in the exact column order the pipeline expects
    input_df = pd.DataFrame([{
        feature: getattr(profile, feature) for feature in FEATURES
    }])

    # predict_proba returns [[prob_non_default, prob_default]]
    prob_default = pipeline.predict_proba(input_df)[0][1]

    # Invert and scale to 0–1000
    score = int((1 - prob_default) * 1000)

    return ScoreResponse(
        score=score,
        probability=round(prob_default, 6),
        model=MODEL_ENV,
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Simple health check — confirms the API is running and model is loaded."""
    return {"status": "ok", "model": MODEL_ENV}


@app.post("/score", response_model=ScoreResponse)
def score(profile: BehavioralProfile):
    """
    Accept a behavioral profile and return a Credora credit score.
    Raw input data is never logged or persisted.
    """
    try:
        return compute_score(profile)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))