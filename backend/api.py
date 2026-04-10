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
from signer import sign_score
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
    nonce:                      int = Field(ge=0)
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
        return v


# ── Response model ────────────────────────────────────────────────────────────

class ScoreResponse(BaseModel):
    score:       int
    probability: float
    model:       str
    wallet:      str
    nonce:       int
    timestamp:   int
    signature:   str
    message:     str

# ── Scoring logic ─────────────────────────────────────────────────────────────

def compute_score(profile: BehavioralProfile, wallet: str) -> ScoreResponse:
    input_df = pd.DataFrame([{
        feature: getattr(profile, feature) for feature in FEATURES
    }])

    prob_default = pipeline.predict_proba(input_df)[0][1]
    score = int((1 - prob_default) * 1000)

    signed = sign_score(wallet=wallet, score=score, nonce=profile.nonce)

    return ScoreResponse(
        score=score,
        probability=round(prob_default, 6),
        model=MODEL_ENV,
        wallet=signed["wallet"],
        nonce=signed["nonce"],
        timestamp=signed["timestamp"],
        signature=signed["signature"],
        message=signed["message"],
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ENV}


@app.post("/score", response_model=ScoreResponse)
def score(profile: BehavioralProfile, wallet: str):
    try:
        return compute_score(profile, wallet)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))