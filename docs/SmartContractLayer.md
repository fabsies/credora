# Credora Smart Contract Layer — Complete Documentation

## Table of Contents

1. [Protocol Overview](#1-protocol-overview)
2. [Architecture](#2-architecture)
3. [Contract Specifications](#3-contract-specifications)
   - 3.1 [CredoraScore.sol](#31-credorascoresol)
   - 3.2 [SoulboundNFT.sol](#32-soulboundnftsol)
   - 3.3 [OracleBridge.sol](#33-oraclebridgesol)
4. [Deployment Script](#4-deployment-script)
5. [Test Suites](#5-test-suites)
   - 5.1 [CredoraScore.t.sol](#51-credorascoretestsol)
   - 5.2 [SoulboundNFT.t.sol](#52-soulboundnfttestsol)
   - 5.3 [OracleBridge.t.sol](#53-oraclebridgetestsol)
6. [Security Model](#6-security-model)
7. [Score Tier System](#7-score-tier-system)
8. [Data Flow & Lifecycle](#8-data-flow--lifecycle)
9. [Admin Operations](#9-admin-operations)
10. [Dependencies](#10-dependencies)
11. [Deployment Guide](#11-deployment-guide)

---

## 1. Protocol Overview

The Credora Smart Contract Layer is a three-contract on-chain protocol that brings ML-computed credit scores onto the blockchain. The system is designed to:

- **Store credit scores** — Persist machine-learning-generated creditworthiness scores (0–10,000 scale) per wallet address with timestamps.
- **Issue non-transferable credentials** — Mint soulbound (non-transferable) ERC-721 NFTs as permanent, on-chain proof of a wallet's credit evaluation.
- **Bridge off-chain data securely** — Validate ECDSA-signed payloads from a backend oracle, enforce replay protection, and orchestrate writes to both the score ledger and the NFT credential contract.

**Target Chain:** Base (Sepolia testnet and Mainnet), though the contracts are chain-agnostic EVM-compatible.  
**Solidity Version:** `^0.8.24`  
**Framework:** Foundry (Forge for compilation/testing, Script for deployment)  
**License:** MIT

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BACKEND (Off-chain)                         │
│                                                                     │
│   ML Scoring API  ──►  ECDSA Signer (ORACLE_PRIVATE_KEY)           │
│                              │                                      │
│                     Signs: (wallet, score, nonce, timestamp)        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │  signature + payload
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       ON-CHAIN (EVM)                                 │
│                                                                      │
│   ┌──────────────────────┐                                           │
│   │    OracleBridge       │ ◄── Entry point for users/backend        │
│   │  (Signature Verifier) │                                          │
│   │  (Replay Protection)  │                                          │
│   │  (Score Tier Mapper)  │                                          │
│   └─────┬────────┬────────┘                                          │
│         │        │                                                   │
│    writeScore()  │  mint()                                           │
│         │        │                                                   │
│         ▼        ▼                                                   │
│   ┌──────────┐  ┌─────────────┐                                     │
│   │ Credora  │  │ Soulbound   │                                     │
│   │  Score   │  │    NFT      │                                     │
│   │ (Ledger) │  │(Credential) │                                     │
│   └──────────┘  └─────────────┘                                     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Dependency Order:**

1. `CredoraScore` — No dependencies (standalone ledger)
2. `SoulboundNFT` — No dependencies (standalone NFT)
3. `OracleBridge` — Depends on both `CredoraScore` and `SoulboundNFT`

After deployment, the `OracleBridge` is configured as:

- The `authorizedOracle` on `CredoraScore` (granting write access)
- The `authorizedMinter` on `SoulboundNFT` (granting mint access)

---

## 3. Contract Specifications

---

### 3.1 CredoraScore.sol

**Purpose:** On-chain ledger for ML-computed credit scores.

**Inheritance:** `Ownable` (OpenZeppelin v5)

**File:** `CredoraScore.sol` — 114 lines, 3,887 bytes

#### State Variables

| Variable           | Type                          | Visibility | Description                                                          |
| ------------------ | ----------------------------- | ---------- | -------------------------------------------------------------------- |
| `scores`           | `mapping(address => uint256)` | `private`  | Maps wallet address to credit score (0–10,000)                       |
| `scoreTimestamps`  | `mapping(address => uint256)` | `private`  | Maps wallet address to the `block.timestamp` of the last score write |
| `authorizedOracle` | `address`                     | `public`   | The single address permitted to call `writeScore()`                  |

#### Events

| Event           | Parameters                                                 | Description                                           |
| --------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| `ScoreUpdated`  | `address indexed wallet, uint256 score, uint256 timestamp` | Emitted every time a score is written or updated      |
| `OracleUpdated` | `address indexed oldOracle, address indexed newOracle`     | Emitted when the authorized oracle address is changed |

#### Custom Errors

| Error               | Trigger                                             |
| ------------------- | --------------------------------------------------- |
| `NotOracle()`       | Caller is not the `authorizedOracle`                |
| `ScoreOutOfRange()` | Score exceeds 10,000                                |
| `ZeroAddress()`     | Zero address passed to constructor or `setOracle()` |

#### Functions

##### `constructor(address _authorizedOracle)`

- Sets the initial `authorizedOracle`
- Passes `msg.sender` to `Ownable` (deployer becomes owner)
- Reverts with `ZeroAddress()` if `_authorizedOracle` is `address(0)`

##### `writeScore(address wallet, uint256 score) external onlyOracle`

- Writes or overwrites a credit score for the given wallet
- Validates `score <= 10000`, otherwise reverts with `ScoreOutOfRange()`
- Records `block.timestamp` as the score timestamp
- Emits `ScoreUpdated`
- **Access:** Only `authorizedOracle`

##### `setOracle(address newOracle) external onlyOwner`

- Updates the `authorizedOracle` address
- Reverts with `ZeroAddress()` if `newOracle` is `address(0)`
- Emits `OracleUpdated`
- **Access:** Only contract owner

##### `getScore(address wallet) public view returns (uint256 score, uint256 timestamp)`

- Returns the stored score and its timestamp for a wallet
- Returns `(0, 0)` for wallets that have never been scored

##### `isScoreFresh(address wallet, uint256 maxAge) public view returns (bool)`

- Returns `true` if the wallet has a score AND [`block.timestamp - scoreTimestamp <= maxAge`]
- Returns `false` if the wallet has never been scored (timestamp == 0)
- Useful for frontends/integrations to check score staleness

---

### 3.2 SoulboundNFT.sol

**Purpose:** Non-transferable ERC-721 credential NFT. Each wallet receives at most one NFT as permanent proof of credit evaluation.

**Inheritance:** `ERC721`, `Ownable` (OpenZeppelin v5)

**File:** `SoulboundNFT.sol` — 208 lines, 6,619 bytes

#### State Variables

| Variable           | Type                         | Visibility | Description                                         |
| ------------------ | ---------------------------- | ---------- | --------------------------------------------------- |
| `_tokenIdCounter`  | `uint256`                    | `private`  | Auto-incrementing token ID, starts at 1             |
| `hasMinted`        | `mapping(address => bool)`   | `public`   | Tracks whether a wallet has already received an NFT |
| `authorizedMinter` | `address`                    | `public`   | The single address permitted to call `mint()`       |
| `_tokenScoreTier`  | `mapping(uint256 => string)` | `private`  | Maps token ID to its score tier label               |

#### ERC-721 Metadata

| Property | Value                       |
| -------- | --------------------------- |
| Name     | `Credora Credit Credential` |
| Symbol   | `CREDORA`                   |

#### Events

| Event           | Parameters                                                      | Description                                   |
| --------------- | --------------------------------------------------------------- | --------------------------------------------- |
| `Minted`        | `address indexed to, uint256 indexed tokenId, string scoreTier` | Emitted when a credential NFT is minted       |
| `MinterUpdated` | `address indexed oldMinter, address indexed newMinter`          | Emitted when the authorized minter is changed |

#### Custom Errors

| Error               | Trigger                                              |
| ------------------- | ---------------------------------------------------- |
| `NotMinter()`       | Caller is not the `authorizedMinter`                 |
| `AlreadyMinted()`   | Wallet has already received an NFT                   |
| `NonTransferable()` | Any transfer, approval, or setApprovalForAll attempt |
| `ZeroAddress()`     | Zero address passed to constructor or `setMinter()`  |

#### Functions

##### `constructor(address _authorizedMinter)`

- Initializes the ERC-721 with name "Credora Credit Credential" and symbol "CREDORA"
- Sets the initial `authorizedMinter`
- Reverts with `ZeroAddress()` if `_authorizedMinter` is `address(0)`

##### `mint(address to, string calldata scoreTier) external onlyMinter`

- Mints a new credential NFT to the wallet `to`
- Reverts with `AlreadyMinted()` if `hasMinted[to]` is already true
- Assigns an auto-incrementing token ID
- Stores the `scoreTier` string against the token ID
- Uses `_safeMint` (ERC-721 safe mint with receiver check)
- Emits `Minted`
- **Access:** Only `authorizedMinter`

##### `setMinter(address newMinter) external onlyOwner`

- Updates the `authorizedMinter`
- Reverts on zero address
- Emits `MinterUpdated`
- **Access:** Only contract owner

##### `getScoreTier(uint256 tokenId) public view returns (string memory)`

- Returns the score tier string for a given token ID
- Reverts if the token does not exist (via `_requireOwned`)

##### `tokenURI(uint256 tokenId) public view override returns (string memory)`

- Returns fully on-chain, Base64-encoded JSON metadata
- JSON includes:
  - `name`: "Credora Credit Credential #\<tokenId\>"
  - `description`: "Non-transferable proof of on-chain creditworthiness"
  - `attributes`: Score Tier and Wallet address
- No external IPFS/server dependency

#### Soulbound Enforcement

The soulbound guarantee is enforced at multiple levels:

1. **`_update()` override (OZ v5 pattern):** Blocks all transfers where `from != address(0)`. Only mints (where `from` is the zero address) are permitted.
2. **`approve()` override:** Always reverts with `NonTransferable()`.
3. **`setApprovalForAll()` override:** Always reverts with `NonTransferable()`.

This triple-layer approach ensures that even if a future ERC-721 extension adds a new transfer path, the `_update` hook will catch it.

#### Internal Utility: `_addressToString(address)`

- Converts an Ethereum address to a lowercase hex string (`0x...`)
- Used internally for generating the tokenURI JSON metadata

---

### 3.3 OracleBridge.sol

**Purpose:** Trusted bridge that validates off-chain ECDSA-signed score payloads, writes verified scores to the on-chain ledger, and mints soulbound credential NFTs.

**Inheritance:** `Ownable`, `ReentrancyGuard` (OpenZeppelin v5)

**File:** `OracleBridge.sol` — 213 lines, 7,160 bytes

#### Interfaces Used

```solidity
interface ICredoraScore {
    function writeScore(address wallet, uint256 score) external;
}

interface ISoulboundNFT {
    function mint(address to, string calldata scoreTier) external;
    function hasMinted(address wallet) external view returns (bool);
}
```

#### State Variables

| Variable          | Type                          | Visibility        | Description                                                      |
| ----------------- | ----------------------------- | ----------------- | ---------------------------------------------------------------- |
| `oracleSigner`    | `address`                     | `public`          | The ECDSA signer address from the backend oracle                 |
| `credoraScore`    | `ICredoraScore`               | `public`          | Reference to the CredoraScore contract                           |
| `soulboundNFT`    | `ISoulboundNFT`               | `public`          | Reference to the SoulboundNFT contract                           |
| `usedNonces`      | `mapping(address => uint256)` | `public`          | Tracks the last used nonce per wallet (monotonically increasing) |
| `MAX_PAYLOAD_AGE` | `uint256`                     | `public constant` | Maximum age for a payload timestamp: **5 minutes**               |

#### Events

| Event                 | Parameters                                                             | Description                                     |
| --------------------- | ---------------------------------------------------------------------- | ----------------------------------------------- |
| `ScoreProcessed`      | `address indexed wallet, uint256 score, uint256 nonce, bool nftMinted` | Emitted after a score is successfully processed |
| `OracleSignerUpdated` | `address indexed oldSigner, address indexed newSigner`                 | Emitted when the oracle signer is changed       |

#### Custom Errors

| Error                | Trigger                                                                |
| -------------------- | ---------------------------------------------------------------------- |
| `ScoreOutOfRange()`  | Score exceeds 10,000                                                   |
| `NonceAlreadyUsed()` | Nonce is not strictly greater than the last used nonce for that wallet |
| `PayloadExpired()`   | `block.timestamp - payload.timestamp > 5 minutes`                      |
| `InvalidSignature()` | Recovered signer does not match `oracleSigner`                         |
| `ZeroAddress()`      | Zero address passed to constructor or admin setters                    |

#### Functions

##### `constructor(address _oracleSigner, address _credoraScore, address _soulboundNFT)`

- Sets the oracle signer, CredoraScore reference, and SoulboundNFT reference
- Validates all three addresses are non-zero
- Passes `msg.sender` to `Ownable`

##### `processScore(address wallet, uint256 score, uint256 nonce, uint256 timestamp, bytes calldata signature) external nonReentrant`

This is the **core function** of the entire protocol. It follows the Checks-Effects-Interactions (CEI) pattern strictly:

**CHECKS Phase:**

1. **Score range:** `score <= 10000`, otherwise `ScoreOutOfRange()`
2. **Nonce monotonicity:** `nonce > usedNonces[wallet]`, otherwise `NonceAlreadyUsed()`
3. **Timestamp freshness:** `block.timestamp - timestamp <= MAX_PAYLOAD_AGE`, otherwise `PayloadExpired()`
4. **ECDSA verification:**
   - Computes `keccak256(abi.encodePacked(wallet, score, nonce, timestamp))`
   - Converts to Ethereum signed message hash
   - Recovers the signer via `ECDSA.recover()`
   - Compares against `oracleSigner`, otherwise `InvalidSignature()`

**EFFECTS Phase:** 5. Updates `usedNonces[wallet] = nonce`

**INTERACTIONS Phase:** 6. Calls `credoraScore.writeScore(wallet, score)` 7. If `!soulboundNFT.hasMinted(wallet)`:

- Derives the score tier via `_getScoreTier(score)`
- Calls `soulboundNFT.mint(wallet, scoreTier)`
- Sets `nftMinted = true`

8. Emits `ScoreProcessed`

**Access:** Anyone can call this function (permissionless relay), but only payloads signed by the `oracleSigner` will succeed.

##### `setOracleSigner(address newSigner) external onlyOwner`

- Updates the oracle signer address
- Emits `OracleSignerUpdated`

##### `setCredoraScore(address addr) external onlyOwner`

- Updates the CredoraScore contract reference

##### `setSoulboundNFT(address addr) external onlyOwner`

- Updates the SoulboundNFT contract reference

##### `getScoreTier(uint256 score) public pure returns (string memory)`

- Public wrapper for `_getScoreTier()` (see [Score Tier System](#7-score-tier-system))

##### `_getScoreTier(uint256 score) internal pure returns (string memory)`

- Maps a numeric score to a tier label string (see [Score Tier System](#7-score-tier-system))

---

## 4. Deployment Script

**File:** `Deploy.s.sol` — 198 lines, 7,158 bytes

The deployment script (`Deploy is Script`) automates the full deployment and configuration sequence using Foundry's `forge script` tooling.

### Environment Variables Required

| Variable               | Description                                |
| ---------------------- | ------------------------------------------ |
| `DEPLOYER_PRIVATE_KEY` | Private key of the deployer wallet         |
| `ORACLE_ADDRESS`       | Public address of the backend ECDSA signer |

### Deployment Sequence

1. **Deploy `CredoraScore`** — Constructor receives the deployer as the initial (temporary) oracle
2. **Deploy `SoulboundNFT`** — Constructor receives the deployer as the initial (temporary) minter
3. **Deploy `OracleBridge`** — Constructor receives the oracle signer address, CredoraScore address, and SoulboundNFT address
4. **Configure Permissions:**
   - `credoraScore.setOracle(address(oracleBridge))` — Transfers write authority to the bridge
   - `soulboundNFT.setMinter(address(oracleBridge))` — Transfers mint authority to the bridge

### Post-Deployment Checks

The script automatically verifies:

- `CredoraScore.authorizedOracle == OracleBridge`
- `CredoraScore.owner == deployer`
- `SoulboundNFT.authorizedMinter == OracleBridge`
- `SoulboundNFT.owner == deployer`
- `OracleBridge.oracleSigner == ORACLE_ADDRESS`
- `OracleBridge.owner == deployer`
- `OracleBridge.credoraScore == CredoraScore` (correct reference)
- `OracleBridge.soulboundNFT == SoulboundNFT` (correct reference)

### Output

The script logs:

- All deployed contract addresses
- Environment variables to add to `frontend/.env.local`
- `forge verify-contract` commands for Basescan verification
- Next steps for production readiness

---

## 5. Test Suites

All tests use Foundry's `forge-std/Test.sol` framework with features including `vm.prank`, `vm.expectRevert`, `vm.expectEmit`, `vm.warp`, `vm.sign`, fuzz testing via `vm.assume` and `bound()`.

---

### 5.1 CredoraScore.t.sol

**File:** `CredoraScore.t.sol` — 263 lines, 8,019 bytes  
**Contract:** `CredoraScoreTest`

#### Test Categories

| Category               | Tests | Description                                                                                                  |
| ---------------------- | ----- | ------------------------------------------------------------------------------------------------------------ |
| **Constructor Tests**  | 2     | Verifies correct initialization and zero-address rejection                                                   |
| **writeScore Tests**   | 5     | Success path, updates, access control, range validation, boundary values (0 and 10,000)                      |
| **getScore Tests**     | 2     | Unscored wallets return (0,0), scored wallets return correct values                                          |
| **isScoreFresh Tests** | 4     | Unscored wallets, within maxAge, beyond maxAge, exact boundary                                               |
| **setOracle Tests**    | 5     | Success path, ownership restriction, zero-address rejection, event emission, authority transfer verification |
| **Fuzz Tests**         | 3     | Random valid scores, random invalid scores, random maxAge/timeElapsed combinations                           |

#### Key Test Scenarios

- **Score overwrite:** Verifies that a second `writeScore` call updates both the score and timestamp
- **Oracle rotation:** After `setOracle(newOracle)`, the old oracle can no longer write and the new oracle can
- **Boundary freshness:** `isScoreFresh` returns `true` when elapsed time equals exactly `maxAge` (inclusive `<=` check)

---

### 5.2 SoulboundNFT.t.sol

**File:** `SoulboundNFT.t.sol` — 362 lines, 10,043 bytes  
**Contract:** `SoulboundNFTTest`  
**Helper:** `MockERC721Receiver` — Mock contract implementing `onERC721Received` for `_safeMint` testing

#### Test Categories

| Category                | Tests | Description                                                                                                                                           |
| ----------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Constructor Tests**   | 2     | Name, symbol, minter, owner verification and zero-address rejection                                                                                   |
| **mint Tests**          | 6     | Success path, incrementing token IDs, duplicate mint rejection, minter access control, hasMinted mapping, tier storage                                |
| **Soulbound Tests**     | 6     | `transferFrom`, `safeTransferFrom`, `safeTransferFrom(data)`, `approve`, `setApprovalForAll`, operator transfer — all revert with `NonTransferable()` |
| **tokenURI Tests**      | 3     | Valid Base64 JSON output, content length, nonexistent token revert                                                                                    |
| **getScoreTier Tests**  | 3     | Single tier, nonexistent token, all five tiers                                                                                                        |
| **setMinter Tests**     | 4     | Success path, ownership restriction, zero-address rejection, authority transfer                                                                       |
| **View Function Tests** | 4     | `balanceOf` before/after mint, `ownerOf` success, nonexistent token revert                                                                            |
| **Fuzz Tests**          | 2     | Arbitrary tier strings, variable user counts (1–20)                                                                                                   |
| **Edge Case Tests**     | 2     | Minting to a contract address, `getApproved` always returns zero                                                                                      |

#### Key Test Scenarios

- **Complete soulbound guarantee:** Every ERC-721 transfer vector is tested and confirmed to revert
- **Contract recipient:** `_safeMint` is tested with a contract that implements `onERC721Received`
- **Multi-user fuzz:** Up to 20 users minted in a loop to verify token ID sequencing and hasMinted consistency

---

### 5.3 OracleBridge.t.sol

**File:** `OracleBridge.t.sol` — 518 lines, 16,901 bytes  
**Contract:** `OracleBridgeTest`

#### Setup

The test setup deploys the full three-contract system:

- Creates an oracle keypair (`oraclePrivateKey = 0xA11CE`)
- Creates a wrong signer keypair for negative tests (`wrongPrivateKey = 0xBAD`)
- Deploys `CredoraScore` and `SoulboundNFT` with temporary authorities
- Deploys `OracleBridge` and configures it as the authorized oracle/minter

#### Helper: `_createSignature`

```solidity
function _createSignature(
    address wallet,
    uint256 score,
    uint256 nonce,
    uint256 timestamp,
    uint256 privateKey
) internal pure returns (bytes memory)
```

Generates a valid ECDSA signature matching the on-chain verification logic:

1. `keccak256(abi.encodePacked(wallet, score, nonce, timestamp))`
2. Prefixed with `"\x19Ethereum Signed Message:\n32"`
3. Signed via `vm.sign(privateKey, ...)`
4. Returned as `abi.encodePacked(r, s, v)`

#### Test Categories

| Category                               | Tests | Description                                                                                            |
| -------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------ |
| **Constructor Tests**                  | 4     | Success, and zero-address rejection for each of the three constructor parameters                       |
| **processScore (Happy Path)**          | 4     | Full success, score written correctly, NFT minted with correct tier, score update without re-mint      |
| **processScore (Validation Failures)** | 5     | Out-of-range score, reused nonce, expired timestamp, invalid signature, exact 5-minute boundary        |
| **Nonce Monotonicity Tests**           | 2     | Strict increase enforcement, cannot go backwards                                                       |
| **Score Tier Mapping Tests**           | 5     | DEVELOPING, FAIR, GOOD, STRONG, EXCEPTIONAL — boundary values for each                                 |
| **Admin Function Tests**               | 6     | `setOracleSigner`, `setCredoraScore`, `setSoulboundNFT` — success, ownership restriction, zero-address |
| **Integration Tests**                  | 2     | Multi-user full flow (two different tiers), score update without NFT re-mint                           |
| **Fuzz Tests**                         | 2     | Random valid scores (0–10,000), monotonic nonce sequences (1–20 iterations)                            |

#### Key Test Scenarios

- **End-to-end integration:** Two users with different scores/tiers receive correct scores and NFTs
- **NFT immutability:** After a score update, the NFT retains its original tier (the credential is a snapshot)
- **Boundary precision:** Payload at exactly 5 minutes old is accepted; at 6 minutes it is rejected
- **Nonce skip-back:** After using nonce 5, attempting nonce 3 reverts

---

## 6. Security Model

### Access Control Matrix

| Action                      | CredoraScore            | SoulboundNFT            | OracleBridge             |
| --------------------------- | ----------------------- | ----------------------- | ------------------------ |
| Write score                 | `authorizedOracle` only | —                       | —                        |
| Mint NFT                    | —                       | `authorizedMinter` only | —                        |
| Process score payload       | —                       | —                       | Anyone (signature-gated) |
| Change oracle/minter/signer | Owner only              | Owner only              | Owner only               |
| Change contract references  | —                       | —                       | Owner only               |
| Transfer ownership          | Owner only              | Owner only              | Owner only               |

### Anti-Exploit Protections

| Threat                     | Protection                                                   | Contract      |
| -------------------------- | ------------------------------------------------------------ | ------------- |
| **Replay attack**          | Monotonically increasing nonce per wallet                    | OracleBridge  |
| **Stale payload**          | 5-minute maximum payload age                                 | OracleBridge  |
| **Forged payload**         | ECDSA signature verification against `oracleSigner`          | OracleBridge  |
| **Reentrancy**             | `nonReentrant` modifier on `processScore`                    | OracleBridge  |
| **Unauthorized writes**    | `onlyOracle` modifier                                        | CredoraScore  |
| **Unauthorized mints**     | `onlyMinter` modifier                                        | SoulboundNFT  |
| **Token transfer**         | `_update()` override blocks all non-mint transfers           | SoulboundNFT  |
| **Token approval**         | `approve()` and `setApprovalForAll()` always revert          | SoulboundNFT  |
| **Duplicate credentials**  | `hasMinted` mapping enforces one NFT per wallet              | SoulboundNFT  |
| **Score overflow**         | Score capped at 10,000 in both CredoraScore and OracleBridge | Both          |
| **Zero address injection** | All constructors and admin setters reject `address(0)`       | All contracts |

### Checks-Effects-Interactions (CEI) Pattern

The `processScore` function in `OracleBridge` strictly follows CEI:

1. **Checks** — All validation (score range, nonce, timestamp, signature) happens first
2. **Effects** — State mutation (`usedNonces[wallet] = nonce`) happens before external calls
3. **Interactions** — External calls (`writeScore`, `mint`) happen last

This ordering, combined with the `nonReentrant` guard, provides defense-in-depth against reentrancy.

---

## 7. Score Tier System

Scores map to five named tiers:

| Score Range    | Tier Label    | Description                         |
| -------------- | ------------- | ----------------------------------- |
| 0 – 1,999      | `DEVELOPING`  | Early-stage or low creditworthiness |
| 2,000 – 3,999  | `FAIR`        | Below-average creditworthiness      |
| 4,000 – 5,999  | `GOOD`        | Average creditworthiness            |
| 6,000 – 7,999  | `STRONG`      | Above-average creditworthiness      |
| 8,000 – 10,000 | `EXCEPTIONAL` | Top-tier creditworthiness           |

**Tier assignment is immutable on the NFT.** When a score is first processed for a wallet, an NFT is minted with the tier corresponding to the **initial** score. If the score is later updated via a new `processScore` call, the NFT's tier remains unchanged (the original credential is preserved). Only the numeric score in the `CredoraScore` contract is updated.

---

## 8. Data Flow & Lifecycle

### First Score Submission (New Wallet)

```
1. Backend ML API computes score for wallet
2. Backend signs (wallet, score, nonce=1, timestamp) with ORACLE_PRIVATE_KEY
3. Transaction calls OracleBridge.processScore(wallet, score, 1, timestamp, signature)
4. OracleBridge validates:
   - Score ≤ 10,000 ✓
   - Nonce 1 > 0 (last used) ✓
   - Timestamp within 5 minutes ✓
   - Signature matches oracleSigner ✓
5. OracleBridge sets usedNonces[wallet] = 1
6. OracleBridge calls CredoraScore.writeScore(wallet, score)
   - CredoraScore stores score and block.timestamp
   - Emits ScoreUpdated
7. OracleBridge checks soulboundNFT.hasMinted(wallet) → false
   - Derives tier from score (e.g., 7500 → "STRONG")
   - Calls SoulboundNFT.mint(wallet, "STRONG")
   - SoulboundNFT mints token ID 1 to wallet
   - Emits Minted
8. OracleBridge emits ScoreProcessed(wallet, 7500, 1, true)
```

### Score Update (Existing Wallet)

```
1. Backend computes updated score
2. Backend signs (wallet, newScore, nonce=2, timestamp) with ORACLE_PRIVATE_KEY
3. Transaction calls OracleBridge.processScore(wallet, newScore, 2, timestamp, signature)
4. OracleBridge validates all checks (nonce 2 > 1 ✓)
5. OracleBridge sets usedNonces[wallet] = 2
6. OracleBridge calls CredoraScore.writeScore(wallet, newScore)
   - Score and timestamp updated
7. OracleBridge checks soulboundNFT.hasMinted(wallet) → true
   - NFT NOT re-minted (skipped)
8. OracleBridge emits ScoreProcessed(wallet, newScore, 2, false)
```

---

## 9. Admin Operations

### Rotating the Oracle Signer

If the backend's signing key is compromised or rotated:

```solidity
// Only contract owner can call
oracleBridge.setOracleSigner(newSignerAddress);
```

Old signatures will fail validation. New payloads must be signed with the new key.

### Upgrading Contract References

If `CredoraScore` or `SoulboundNFT` are redeployed:

```solidity
oracleBridge.setCredoraScore(newCredoraScoreAddress);
oracleBridge.setSoulboundNFT(newSoulboundNFTAddress);
```

> **Warning:** The new contracts must also authorize the OracleBridge as their oracle/minter.

### Transferring Ownership

All three contracts inherit `Ownable`, so ownership can be transferred:

```solidity
credoraScore.transferOwnership(multisigAddress);
soulboundNFT.transferOwnership(multisigAddress);
oracleBridge.transferOwnership(multisigAddress);
```

> **Important:** For mainnet, ownership should be transferred to a multisig wallet before launch.

---

## 10. Dependencies

### OpenZeppelin Contracts v5

| Import                                                            | Used By             | Purpose                               |
| ----------------------------------------------------------------- | ------------------- | ------------------------------------- |
| `@openzeppelin/contracts/access/Ownable.sol`                      | All three contracts | Owner-only admin functions            |
| `@openzeppelin/contracts/token/ERC721/ERC721.sol`                 | SoulboundNFT        | ERC-721 NFT standard                  |
| `@openzeppelin/contracts/utils/Base64.sol`                        | SoulboundNFT        | On-chain Base64 encoding for tokenURI |
| `@openzeppelin/contracts/utils/Strings.sol`                       | SoulboundNFT        | uint256-to-string conversion          |
| `@openzeppelin/contracts/utils/ReentrancyGuard.sol`               | OracleBridge        | Reentrancy protection                 |
| `@openzeppelin/contracts/utils/cryptography/ECDSA.sol`            | OracleBridge        | Signature recovery                    |
| `@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol` | OracleBridge        | Ethereum signed message hash prefix   |

### Foundry

| Import                 | Used By        | Purpose                                |
| ---------------------- | -------------- | -------------------------------------- |
| `forge-std/Test.sol`   | All test files | Test framework, cheatcodes, assertions |
| `forge-std/Script.sol` | Deploy.s.sol   | Deployment scripting                   |

---

## 11. Deployment Guide

### Prerequisites

- Foundry installed (`forge`, `cast`)
- `.env` file with `DEPLOYER_PRIVATE_KEY` and `ORACLE_ADDRESS`
- Funded deployer wallet on target chain

### Commands

```bash
# Compile contracts
forge build

# Run all tests
forge test

# Run tests with verbosity for detailed output
forge test -vvv

# Deploy to Base Sepolia
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify

# Deploy to Base Mainnet
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_MAINNET_RPC \
  --broadcast \
  --verify
```

### Post-Deployment Checklist

1. Copy deployed contract addresses to `frontend/.env.local`:
   - `NEXT_PUBLIC_CREDORA_SCORE_ADDRESS`
   - `NEXT_PUBLIC_SOULBOUND_NFT_ADDRESS`
   - `NEXT_PUBLIC_ORACLE_BRIDGE_ADDRESS`

2. Verify contracts on Basescan:

   ```bash
   forge verify-contract <ADDRESS> <CONTRACT> --chain-id <CHAIN_ID>
   ```

3. Test with cast calls:

   ```bash
   cast call <CREDORA_SCORE_ADDR> 'authorizedOracle()' --rpc-url <RPC>
   ```

4. **For Mainnet:** Transfer ownership of all three contracts to a multisig before launch.

---

## File Summary

| File                 | Type     | Lines     | Size         | Description                            |
| -------------------- | -------- | --------- | ------------ | -------------------------------------- |
| `CredoraScore.sol`   | Contract | 114       | 3,887 B      | Credit score ledger                    |
| `SoulboundNFT.sol`   | Contract | 208       | 6,619 B      | Non-transferable credential NFT        |
| `OracleBridge.sol`   | Contract | 213       | 7,160 B      | Signature-verified oracle bridge       |
| `CredoraScore.t.sol` | Test     | 263       | 8,019 B      | 21 tests including 3 fuzz tests        |
| `SoulboundNFT.t.sol` | Test     | 362       | 10,043 B     | 30 tests including 2 fuzz tests        |
| `OracleBridge.t.sol` | Test     | 518       | 16,901 B     | 30 tests including 2 fuzz tests        |
| `Deploy.s.sol`       | Script   | 198       | 7,158 B      | Automated deployment with verification |
| **Total**            | —        | **1,876** | **59,787 B** | —                                      |
