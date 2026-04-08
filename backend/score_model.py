# score_model.py
# Credora — ML Scoring Model Trainer
#
# Trains a GradientBoostingClassifier Pipeline on the synthetic behavioral
# financial dataset produced by data_generator.py.
#
# Pipeline stages:
#   1. SimpleImputer   — fills missing values with column medians
#   2. StandardScaler  — normalizes all features to the same scale
#   3. GradientBoostingClassifier — the core credit scoring model
#
# Output: a versioned .joblib file saved to backend/models/
#
# NOTE: All training data is synthetic. See data_generator.py for details.

import joblib
import numpy as np
import pandas as pd
from datetime import date
from pathlib import Path

from sklearn.ensemble import GradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import roc_auc_score, classification_report
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.utils.class_weight import compute_sample_weight

# ── Constants ─────────────────────────────────────────────────────────────────

DATA_PATH  = Path(__file__).parent / "data"  / "credora_synthetic_v1.csv"
MODELS_DIR = Path(__file__).parent / "models"

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

TARGET = "default"
RANDOM_SEED = 42

# ── Load data ─────────────────────────────────────────────────────────────────

def load_data(path: Path = DATA_PATH):
    """
    Load the synthetic dataset from CSV.
    Returns X (features) and y (target) as separate objects.
    """
    print(f"[score_model] Loading data from {path}")
    df = pd.read_csv(path)
    print(f"[score_model] Dataset shape: {df.shape}")
    print(f"[score_model] Default rate: {df[TARGET].mean():.2%}")

    X = df[FEATURES]
    y = df[TARGET]
    return X, y

# ── Build pipeline ────────────────────────────────────────────────────────────

def build_pipeline() -> Pipeline:
    """
    Construct the three-stage sklearn Pipeline.

    Stage 1 — SimpleImputer:
        Fills NaN values with the median of each column.
        Median is more robust than mean for skewed financial data.

    Stage 2 — StandardScaler:
        Rescales every feature to mean=0, std=1.
        Gradient boosting doesn't strictly need this, but it makes
        the model more stable and the feature importances comparable.

    Stage 3 — GradientBoostingClassifier:
        The core model. Key parameters:
          n_estimators   — 300 trees (more trees = better, up to a point)
          learning_rate  — 0.05 (slow learning rate + more trees = better generalisation)
          max_depth      — 4 (shallow trees reduce overfitting)
          subsample      — 0.8 (use 80% of rows per tree, adds randomness)
          n_iter_no_change — 20 (stop early if no improvement after 20 rounds)
    """
    pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="median")),
        ("scaler",  StandardScaler()),
        ("model",   GradientBoostingClassifier(
            n_estimators=300,
            learning_rate=0.05,
            max_depth=4,
            subsample=0.8,
            n_iter_no_change=20,
            random_state=RANDOM_SEED,
            verbose=1,
        )),
    ])
    return pipeline

# ── Train ─────────────────────────────────────────────────────────────────────

def train(X, y) -> tuple:
    """
    Split the data, compute sample weights to handle class imbalance,
    train the pipeline, and return the trained pipeline + test split.

    Why sample_weight instead of class_weight?
    GradientBoostingClassifier doesn't accept class_weight directly.
    compute_sample_weight('balanced', y) gives each sample a weight
    that is inversely proportional to how common its class is —
    so the 12% of defaulters get ~7x more influence during training.
    """
    print("[score_model] Splitting data 80/20 train/test...")
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_SEED, stratify=y
    )

    # Compute sample weights on training set only
    sample_weights = compute_sample_weight(class_weight="balanced", y=y_train)

    pipeline = build_pipeline()

    print("[score_model] Training pipeline...")
    # Pass sample weights to the final step (the model) via the pipeline
    pipeline.fit(
        X_train,
        y_train,
        model__sample_weight=sample_weights,
    )

    return pipeline, X_test, y_test

# ── Evaluate ──────────────────────────────────────────────────────────────────

def evaluate(pipeline: Pipeline, X_test, y_test):
    """
    Print AUC-ROC, Gini coefficient, and a full classification report.

    AUC-ROC:  primary metric for credit models — measures how well
              the model separates defaulters from non-defaulters.
              0.5 = random, 1.0 = perfect. Aim for > 0.85.

    Gini:     standard lending industry metric = (2 × AUC) - 1.
              0 = random, 1 = perfect. Aim for > 0.70.
    """
    print("[score_model] Evaluating on test set...")

    y_prob = pipeline.predict_proba(X_test)[:, 1]
    y_pred = pipeline.predict(X_test)

    auc  = roc_auc_score(y_test, y_prob)
    gini = 2 * auc - 1

    print(f"\n{'─' * 40}")
    print(f"  AUC-ROC : {auc:.4f}")
    print(f"  Gini    : {gini:.4f}")
    print(f"{'─' * 40}\n")
    print(classification_report(y_test, y_pred, target_names=["non-default", "default"]))

    # Feature importances — useful for model card and explainability
    importances = pipeline.named_steps["model"].feature_importances_
    importance_df = pd.DataFrame({
        "feature":   FEATURES,
        "importance": importances,
    }).sort_values("importance", ascending=False)

    print("Feature importances:")
    print(importance_df.to_string(index=False))

# ── Save ──────────────────────────────────────────────────────────────────────

def save(pipeline: Pipeline) -> Path:
    """
    Serialize the trained pipeline to a versioned .joblib file.
    Filename format: credora_model_v1_YYYYMMDD.joblib
    Never overwrites an existing file.
    """
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    today     = date.today().strftime("%Y%m%d")
    filename  = f"credora_model_v1_{today}.joblib"
    save_path = MODELS_DIR / filename

    if save_path.exists():
        raise FileExistsError(
            f"[score_model] Model file already exists: {save_path}\n"
            "Bump the version number rather than overwriting."
        )

    joblib.dump(pipeline, save_path)
    print(f"\n[score_model] Model saved to {save_path}")
    return save_path

# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    X, y          = load_data()
    pipeline, X_test, y_test = train(X, y)
    evaluate(pipeline, X_test, y_test)
    save(pipeline)
    print("[score_model] Done.")

