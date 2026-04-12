#!/usr/bin/env bash
set -euo pipefail

# Credora deployment budget calculator for Base.
# Static total gas from your current deployment flow:
#   - CredoraScore deploy
#   - SoulboundNFT deploy
#   - OracleBridge deploy
#   - setOracle
#   - setMinter
STATIC_TOTAL_GAS=2929255
BASE_RPC_URL="https://mainnet.base.org"
COINGECKO_URL="https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=kes"
GAS_REPORT_FILE=""

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--gas-mode <static|auto>] [--gwei <value>] [--eth-kes <rate>] [--buffer <percent>]

Options:
  --gas-mode <mode>    static (default) uses hardcoded gas total; auto runs forge gas report and parses current values.
  --gwei <value>      Gas price in gwei. If omitted, fetches live from Base RPC.
  --eth-kes <rate>    ETH/KES rate. If omitted, fetches live from CoinGecko.
  --buffer <percent>  Safety buffer percent for max budget (default: 30).
  -h, --help          Show this help.

Examples:
  $(basename "$0")
  $(basename "$0") --gas-mode auto
  $(basename "$0") --gwei 0.5 --eth-kes 286733
  $(basename "$0") --gwei 1 --buffer 50
EOF
}

parse_metric() {
  local file="$1"
  local contract="$2"
  local metric="$3"
  local value=""

  case "$metric" in
    deploy)
      value=$(awk -F'|' -v c="$contract" '
        $0 ~ c" Contract" {in_contract=1; next}
        in_contract && /^╰/ {in_contract=0}
        in_contract && /\| Deployment Cost/ {
          while (getline > 0) {
            if ($0 ~ /^\|[[:space:]]*[0-9]+[[:space:]]*\|/) {
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
              print $2
              exit
            }
          }
        }
      ' "$file")
      ;;
    setOracleMax)
      value=$(awk -F'|' '/\| setOracle[[:space:]]*\|/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6); print $6; exit}' "$file")
      ;;
    setMinterMax)
      value=$(awk -F'|' '/\| setMinter[[:space:]]*\|/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6); print $6; exit}' "$file")
      ;;
  esac

  echo "$value"
}

compute_total_gas_auto() {
  if ! command -v forge >/dev/null 2>&1; then
    echo "Error: forge not found for --gas-mode auto."
    exit 1
  fi

  GAS_REPORT_FILE=$(mktemp)
  forge test --gas-report >"$GAS_REPORT_FILE"

  local credora_deploy soulbound_deploy bridge_deploy set_oracle_max set_minter_max
  credora_deploy=$(parse_metric "$GAS_REPORT_FILE" "src/CredoraScore.sol:CredoraScore" "deploy")
  soulbound_deploy=$(parse_metric "$GAS_REPORT_FILE" "src/SoulboundNFT.sol:SoulboundNFT" "deploy")
  bridge_deploy=$(parse_metric "$GAS_REPORT_FILE" "src/OracleBridge.sol:OracleBridge" "deploy")
  set_oracle_max=$(parse_metric "$GAS_REPORT_FILE" "" "setOracleMax")
  set_minter_max=$(parse_metric "$GAS_REPORT_FILE" "" "setMinterMax")

  if [[ -z "$credora_deploy" || -z "$soulbound_deploy" || -z "$bridge_deploy" || -z "$set_oracle_max" || -z "$set_minter_max" ]]; then
    echo "Error: failed to parse gas report in auto mode."
    echo "Tip: run with --gas-mode static or inspect forge test --gas-report output."
    exit 1
  fi

  echo $((credora_deploy + soulbound_deploy + bridge_deploy + set_oracle_max + set_minter_max))
}

GWEI=""
ETH_KES=""
BUFFER_PERCENT=30
GAS_MODE="static"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gas-mode)
      GAS_MODE="${2:-}"
      shift 2
      ;;
    --gwei)
      GWEI="${2:-}"
      shift 2
      ;;
    --eth-kes)
      ETH_KES="${2:-}"
      shift 2
      ;;
    --buffer)
      BUFFER_PERCENT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$GAS_MODE" != "static" && "$GAS_MODE" != "auto" ]]; then
  echo "Error: --gas-mode must be 'static' or 'auto'."
  exit 1
fi

if [[ "$GAS_MODE" == "auto" ]]; then
  TOTAL_GAS=$(compute_total_gas_auto)
  GAS_SOURCE="auto (fresh forge gas report)"
else
  TOTAL_GAS="$STATIC_TOTAL_GAS"
  GAS_SOURCE="static (script default)"
fi

if [[ -z "$GWEI" ]]; then
  if ! command -v cast >/dev/null 2>&1; then
    echo "Error: cast not found. Provide --gwei manually or install Foundry."
    exit 1
  fi

  GAS_PRICE_HEX=$(cast rpc --rpc-url "$BASE_RPC_URL" eth_gasPrice | tr -d '"')
  GAS_PRICE_WEI=$(cast --to-dec "$GAS_PRICE_HEX")
  GWEI=$(awk -v w="$GAS_PRICE_WEI" 'BEGIN { printf "%.9f", w/1e9 }')
else
  GAS_PRICE_WEI=$(awk -v g="$GWEI" 'BEGIN { printf "%.0f", g*1e9 }')
fi

if [[ -z "$ETH_KES" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl not found. Provide --eth-kes manually."
    exit 1
  fi

  ETH_KES=$(curl -s "$COINGECKO_URL" | sed -E 's/.*"kes":([0-9.]+).*/\1/')
  if [[ -z "$ETH_KES" || "$ETH_KES" == "{"* ]]; then
    echo "Error: could not parse ETH/KES rate. Provide --eth-kes manually."
    exit 1
  fi
fi

FEE_ETH=$(awk -v gas="$TOTAL_GAS" -v wei="$GAS_PRICE_WEI" 'BEGIN { printf "%.12f", (gas*wei)/1e18 }')
FEE_KES=$(awk -v eth="$FEE_ETH" -v rate="$ETH_KES" 'BEGIN { printf "%.2f", eth*rate }')
MAX_ETH=$(awk -v eth="$FEE_ETH" -v b="$BUFFER_PERCENT" 'BEGIN { printf "%.12f", eth*(1 + b/100) }')
MAX_KES=$(awk -v eth="$MAX_ETH" -v rate="$ETH_KES" 'BEGIN { printf "%.2f", eth*rate }')

cat <<EOF
Credora Deployment Budget (Base Mainnet)
---------------------------------------
Total gas units:        $TOTAL_GAS
Gas source:             $GAS_SOURCE
Gas price:              ${GWEI} gwei (${GAS_PRICE_WEI} wei)
ETH/KES rate:           $ETH_KES

Estimated deploy fee:
  ETH:                  $FEE_ETH
  KES:                  $FEE_KES

Buffered max (+${BUFFER_PERCENT}%):
  ETH:                  $MAX_ETH
  KES:                  $MAX_KES
EOF

if [[ -n "$GAS_REPORT_FILE" && -f "$GAS_REPORT_FILE" ]]; then
  rm -f "$GAS_REPORT_FILE"
fi
