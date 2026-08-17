#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------------------------
# FITMate on-prem — comprehensive Terragrunt runner (Terragrunt 1.1.0 CLI).
#
# One dispatcher for EVERY terragrunt/tofu command against the fitmate tree
# (on-prem/fitmate/<tier>/<unit>). Uses the NEW 1.1.0 CLI: `run --all`, `--non-interactive`,
# `--queue-include-external` (the old `run-all` / `--terragrunt-*` flags are gone).
#
# Usage:
#   ./deployments/on-prem/fitmate/run.sh <command> <tier> [module] [-- <extra tofu/tg args>]
#
#   command : init | validate | plan | apply | destroy | output | refresh | show |
#             state | import | unlock | fmt
#   tier    : shared | dev | stg | prod
#   module  : (optional) a single unit, e.g. vault-auths | vault-secrets |
#             database/trainee | keycloak/fitmate. Omit → run --all across the whole tier.
#
# Examples:
#   run.sh init     shared                      # init every shared unit
#   run.sh validate dev                         # validate all dev units
#   run.sh plan     dev                         # plan the whole dev tier
#   run.sh apply    shared                      # bring up the platform tier
#   run.sh apply    dev  vault-auths            # apply ONE unit
#   run.sh destroy  dev                         # destroy the dev tier (reverse DAG)
#   run.sh output   dev  vault-auths            # -json outputs of one unit
#   run.sh import   dev  database/trainee  'postgresql_database.this["trainee_dev"]'  trainee_dev
#   run.sh state    dev  vault-auths  -- list   # `terragrunt state list` on one unit
#   run.sh unlock   dev  vault-auths  <LOCK_ID> # force-unlock a stuck state lock
#   run.sh fmt      dev                         # terragrunt hcl fmt (whole tier)
#
# Anything after `--` (or trailing args after <module>) is passed straight through to tofu/terragrunt.
# ---------------------------------------------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"        # .../deployments/on-prem/fitmate
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"                # repo root
TENANT="fitmate"
LOCATION="on-prem"
VALID_TIERS="shared dev stg prod"
VALID_CMDS="init validate plan apply destroy output refresh show state import unlock fmt"

usage() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; }

[[ $# -lt 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 2; }

COMMAND="$1"; TIER="$2"; shift 2
MODULE=""
# next bare positional (not a flag, not the -- separator) = single module
if [[ $# -gt 0 && "${1:-}" != "-"* && "${1:-}" != "--" ]]; then MODULE="$1"; shift; fi
[[ "${1:-}" == "--" ]] && shift
PASSTHRU=( "$@" )   # remaining args → passed through to tofu/terragrunt

echo " $VALID_CMDS "  | grep -q " $COMMAND " || { echo "ERROR: command must be one of: $VALID_CMDS" >&2; exit 3; }
echo " $VALID_TIERS " | grep -q " $TIER "    || { echo "ERROR: tier must be one of: $VALID_TIERS" >&2; exit 3; }

# ── logging helpers (optional) ───────────────────────────────────────────────
# shellcheck disable=SC1091
source "${REPO_ROOT}/deployments/utils/utils.sh" 2>/dev/null || true

# ── env vars: source deployments/on-prem/fitmate/envs/<tier>/*.bash ───────────
# (copy *.bash.example → *.bash and fill in; the real *.bash MUST be gitignored — it holds secrets)
ENV_DIR="${SCRIPT_DIR}/envs/${TIER}"
shopt -s nullglob
ENV_FILES=( "${ENV_DIR}"/*.bash )
shopt -u nullglob
if [[ ${#ENV_FILES[@]} -eq 0 ]]; then
  echo "WARN: no env files in ${ENV_DIR} — relying on your current shell env (VAULT_ADDR/VAULT_TOKEN/PG_*/…)." >&2
else
  for f in "${ENV_FILES[@]}"; do
    # shellcheck disable=SC1090
    source "$f" "$TIER" || { echo "FATAL: failed sourcing $f" >&2; exit 1; }
  done
fi

# ── target unit dir ──────────────────────────────────────────────────────────
TARGET="${REPO_ROOT}/${LOCATION}/${TENANT}/${TIER}"
[[ -n "$MODULE" ]] && TARGET="${TARGET}/${MODULE}"
[[ -d "$TARGET" ]] || { echo "ERROR: not a directory: ${TARGET#$REPO_ROOT/}" >&2; exit 4; }
cd "$TARGET"

RUN_ALL=true; [[ -n "$MODULE" ]] && RUN_ALL=false

# ── terragrunt (global) flags + tofu args ────────────────────────────────────
TG_FLAGS=( --non-interactive ) # --no-color
TF_ARGS=()
case "$COMMAND" in
  apply|destroy) TF_ARGS=( -auto-approve ) ;;   # non-interactive apply/destroy
  output)        TF_ARGS=( -json ) ;;
esac

# ── special commands that are NOT plain `run` shortcuts ──────────────────────
case "$COMMAND" in
  fmt)                                            # config command; formats the whole (sub)tree
    set -x; exec terragrunt hcl fmt ${PASSTHRU[@]+"${PASSTHRU[@]}"} ;;
  import)                                         # single-unit only: needs <ADDRESS> <ID>
    $RUN_ALL && { echo "ERROR: 'import' needs a <module> plus <ADDRESS> <ID>." >&2; exit 5; }
    set -x; exec terragrunt run "${TG_FLAGS[@]}" -- import ${PASSTHRU[@]+"${PASSTHRU[@]}"} ;;
  unlock)                                         # single-unit only: needs <LOCK_ID>
    $RUN_ALL && { echo "ERROR: 'unlock' needs a <module> plus <LOCK_ID>." >&2; exit 5; }
    set -x; exec terragrunt run "${TG_FLAGS[@]}" -- force-unlock ${PASSTHRU[@]+"${PASSTHRU[@]}"} ;;
esac

# ── normal run: single unit vs whole tier ────────────────────────────────────
# --queue-include-external pulls in cross-tier deps (dev/stg/prod depend on shared/vault-auths).
# Drop it (or apply `shared` first, then a lower tier) if you want strict per-tier isolation.
LOG_DIR="/tmp/terragrunt/fitmate"; mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${COMMAND}-${TIER}${MODULE:+-${MODULE//\//_}}.log"

if $RUN_ALL; then
  set -x
  terragrunt run --all "${TG_FLAGS[@]}" --queue-include-external -- "$COMMAND" \
    ${TF_ARGS[@]+"${TF_ARGS[@]}"} ${PASSTHRU[@]+"${PASSTHRU[@]}"} 2>&1 | tee "$LOG_FILE"
else
  set -x
  terragrunt run "${TG_FLAGS[@]}" -- "$COMMAND" \
    ${TF_ARGS[@]+"${TF_ARGS[@]}"} ${PASSTHRU[@]+"${PASSTHRU[@]}"} 2>&1 | tee "$LOG_FILE"
fi
exit "${PIPESTATUS[0]}"
