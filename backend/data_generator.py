# data_generator.py
# Credora — Synthetic Behavioral Financial Data Generator
#
# IMPORTANT: All data produced by this module is entirely synthetic.
# It does not represent real individuals or real financial behavior.
# Generated dataset is used exclusively for training and evaluating
# the Credora ML scoring model.
#
# Dataset spec:
#   - 5,000 rows
#   - 12% default rate (~600 defaulters, ~4,400 non-defaulters)
#   - 12 behavioral features across 6 categories
#   - Realistic noise and missing values included
import numpy as np
import pandas as pd
from pathlib import Path
# ── Constants ────────────────────────────────────────────────────────────────
RANDOM_SEED = 42
N_SAMPLES = 5000
DEFAULT_RATE = 0.12
OUTPUT_DIR = Path(__file__).parent / "data"
OUTPUT_FILENAME = "credora_synthetic_v1.csv"
# ── Helper: generate one cohort of profiles ──────────────────────────────────
def _generate_profiles(n: int, is_defaulter: bool, rng: np.random.Generator) -> pd.DataFrame:
    """
    Generate n behavioral profiles.
    Defaulters have weaker signals across all feature categories.
    Non-defaulters have stronger, more consistent signals.
    """
    if is_defaulter:
        # Defaulters — irregular, low-volume, short history
        days_between_payments_mean = rng.uniform(8, 30, n)
        days_between_payments_std  = rng.uniform(8, 20, n)
        missed_payment_count       = rng.integers(1, 8, n)
        monthly_transaction_count  = rng.uniform(8, 20, n)
        monthly_transaction_value  = rng.uniform(3000, 25000, n)
        remittance_frequency       = rng.uniform(0, 1, n)
        remittance_recency_days    = rng.uniform(10, 90, n)
        airtime_topup_frequency    = rng.uniform(0.5, 2, n)
        airtime_topup_avg_amount   = rng.uniform(20, 100, n)
        weekend_activity_ratio     = rng.uniform(0.1, 0.4, n)
        month_end_spike_ratio      = rng.uniform(0.5, 1.2, n)
        account_longevity_months   = rng.uniform(6, 30, n)
    else:
        # Non-defaulters — consistent, higher-volume, longer history
        days_between_payments_mean = rng.uniform(5, 22, n)
        days_between_payments_std  = rng.uniform(1, 8, n)
        missed_payment_count       = rng.integers(0, 4, n)
        monthly_transaction_count  = rng.uniform(10, 25, n)
        monthly_transaction_value  = rng.uniform(5000, 20000, n)
        remittance_frequency       = rng.uniform(1, 5, n)
        remittance_recency_days    = rng.uniform(5, 50, n)
        airtime_topup_frequency    = rng.uniform(2, 8, n)
        airtime_topup_avg_amount   = rng.uniform(100, 500, n)
        weekend_activity_ratio     = rng.uniform(0.3, 0.6, n)
        month_end_spike_ratio      = rng.uniform(1.2, 2.5, n)
        account_longevity_months   = rng.uniform(10, 45, n)

    return pd.DataFrame({
        "days_between_payments_mean": days_between_payments_mean,
        "days_between_payments_std":  days_between_payments_std,
        "missed_payment_count":       missed_payment_count,
        "monthly_transaction_count":  monthly_transaction_count,
        "monthly_transaction_value":  monthly_transaction_value,
        "remittance_frequency":       remittance_frequency,
        "remittance_recency_days":    remittance_recency_days,
        "airtime_topup_frequency":    airtime_topup_frequency,
        "airtime_topup_avg_amount":   airtime_topup_avg_amount,
        "weekend_activity_ratio":     weekend_activity_ratio,
        "month_end_spike_ratio":      month_end_spike_ratio,
        "account_longevity_months":   account_longevity_months,
    })
# ── Main generator ────────────────────────────────────────────────────────────
def generate(n_samples: int = N_SAMPLES,
             default_rate: float = DEFAULT_RATE,
             seed: int = RANDOM_SEED) -> pd.DataFrame:
    """
    Generate a synthetic behavioral financial dataset.

    Args:
        n_samples:    Total number of profiles to generate.
        default_rate: Fraction of profiles that are defaulters.
        seed:         Random seed for reproducibility.

    Returns:
        A pandas DataFrame with 12 feature columns and a binary `default` label.
    """
    rng = np.random.default_rng(seed)

    n_defaulters     = int(n_samples * default_rate)
    n_non_defaulters = n_samples - n_defaulters

    defaulters     = _generate_profiles(n_defaulters,     is_defaulter=True,  rng=rng)
    non_defaulters = _generate_profiles(n_non_defaulters, is_defaulter=False, rng=rng)

    defaulters["default"]     = 1
    non_defaulters["default"] = 0

    df = pd.concat([defaulters, non_defaulters], ignore_index=True)

    # Shuffle so defaulters and non-defaulters aren't in two clean blocks
    df = df.sample(frac=1, random_state=seed).reset_index(drop=True)

    # Inject realistic missing values (~3% of cells in selected columns)
    missing_cols = [
        "remittance_frequency",
        "remittance_recency_days",
        "airtime_topup_avg_amount",
    ]
    for col in missing_cols:
        mask = rng.random(len(df)) < 0.03
        df.loc[mask, col] = np.nan

    return df


# ── Save to disk ──────────────────────────────────────────────────────────────
def save(df: pd.DataFrame,
         output_dir: Path = OUTPUT_DIR,
         filename: str = OUTPUT_FILENAME) -> Path:
    """
    Save the generated dataset to a CSV file inside backend/data/.

    Args:
        df:         The DataFrame to save.
        output_dir: Directory to write into (created if it doesn't exist).
        filename:   Output filename.

    Returns:
        The full path of the saved file.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / filename
    df.to_csv(output_path, index=False)
    print(f"[data_generator] Saved {len(df)} rows to {output_path}")
    return output_path
# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("[data_generator] Generating synthetic dataset...")
    df = generate()
    print(f"[data_generator] Dataset shape: {df.shape}")
    print(f"[data_generator] Default rate: {df['default'].mean():.2%}")
    print(f"[data_generator] Missing values:\n{df.isnull().sum()}")
    save(df)
    print("[data_generator] Done.")
