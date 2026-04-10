# signer.py
# Credora — ECDSA Score Payload Signer
#
# Signs score payloads before they are sent to OracleBridge.sol.
# OracleBridge.sol verifies this signature on-chain using ecrecover.
#
# The signed message contains:
#   - wallet address (who the score belongs to)
#   - score (0–1000)
#   - nonce (prevents replay attacks)
#   - timestamp (for score staleness checks)
#
# The private key never leaves the backend — it lives in .env only.

import hashlib
import hmac
import os
import time

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import (
    decode_dss_signature,
)
from dotenv import load_dotenv

load_dotenv()

# ── Load signing key ──────────────────────────────────────────────────────────

def _load_private_key() -> ec.EllipticCurvePrivateKey:
    """
    Load the ECDSA private key from the CREDORA_SIGNING_KEY env variable.
    The key is stored as a base64 DER string in .env.
    """
    raw = os.getenv("CREDORA_SIGNING_KEY")
    if not raw:
        raise RuntimeError(
            "CREDORA_SIGNING_KEY is not set in .env. "
            "Run the keygen script to generate a keypair."
        )

    # Strip quotes if present
    raw = raw.strip().strip('"').strip("'")

    # Decode from base64 DER
    import base64
    der_bytes = base64.b64decode(raw)

    return serialization.load_der_private_key(der_bytes, password=None)


_private_key = _load_private_key()

# ── Build message ─────────────────────────────────────────────────────────────

def _build_message(wallet: str, score: int, nonce: int, timestamp: int) -> bytes:
    """
    Build the message that will be signed.
    Format: wallet:score:nonce:timestamp
    This exact format must be replicated in OracleBridge.sol for verification.
    """
    message = f"{wallet.lower()}:{score}:{nonce}:{timestamp}"
    return message.encode("utf-8")


def _hash_message(message: bytes) -> bytes:
    """
    Hash the message with SHA256 before signing.
    Matches the on-chain keccak256 hashing in OracleBridge.sol.
    """
    return hashlib.sha256(message).digest()

# ── Sign ──────────────────────────────────────────────────────────────────────

def sign_score(wallet: str, score: int, nonce: int) -> dict:
    """
    Sign a score payload for a given wallet address.

    Args:
        wallet:  The user's wallet address (e.g. "0xabc123...")
        score:   The 0–1000 Credora score
        nonce:   Per-wallet nonce to prevent replay attacks

    Returns:
        A dict containing:
          wallet:     the wallet address (lowercased)
          score:      the score
          nonce:      the nonce
          timestamp:  unix timestamp of signing
          signature:  hex-encoded DER signature
          message:    the raw message that was signed (for debugging)
    """
    timestamp = int(time.time())
    message   = _build_message(wallet, score, nonce, timestamp)
    digest    = _hash_message(message)

    # Sign with ECDSA
    signature_der = _private_key.sign(message, ec.ECDSA(hashes.SHA256()))
    # Encode signature as hex for transport
    signature_hex = signature_der.hex()

    return {
        "wallet":    wallet.lower(),
        "score":     score,
        "nonce":     nonce,
        "timestamp": timestamp,
        "signature": signature_hex,
        "message":   message.decode("utf-8"),
    }


# ── Verify (for testing only) ─────────────────────────────────────────────────

def verify_score(signed_payload: dict) -> bool:
    """
    Verify a signed payload using the public key.
    This is used in tests only — on-chain verification is done by OracleBridge.sol.
    """
    public_key = _private_key.public_key()

    message   = _build_message(
        signed_payload["wallet"],
        signed_payload["score"],
        signed_payload["nonce"],
        signed_payload["timestamp"],
    )
    digest    = _hash_message(message)
    signature = bytes.fromhex(signed_payload["signature"])

    try:
        public_key.verify(signature, message, ec.ECDSA(hashes.SHA256()))
        return True
    except Exception:
        return False