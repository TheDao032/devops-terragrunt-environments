#!/usr/bin/env bash

# ---------------------------------------------------------------------------------------------------------------------
# Run terragrunt init/validate/plan for a tenant + environment under on-prem.
#
# Usage:
#   ./deployments/on-prem/build.sh <tenant> <environment> [module]
#
# Examples:
#   ./deployments/on-prem/build.sh bosch   local
#   ./deployments/on-prem/build.sh renesas dev jenkins
#
# Tenants live at:  on-prem/<tenant>/<environment>/<module>/terragrunt.hcl
# Tenant env-vars:  deployments/on-prem/<tenant>/envs/<environment>/*.bash
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <tenant> <environment> [module]

  tenant       e.g. bosch | renesas
  environment  e.g. local | dev | stg | prod
  module       (optional) single resource to act on; default = all

Optional positional args (advanced):
  4: INIT_LOG_FILE_NAME      (default: init-<env>.log)
  5: VALIDATE_LOG_FILE_NAME  (default: validate-<env>.log)
  6: PLAN_LOG_FILE_NAME      (default: plan-<env>.log)
EOF
}

if [[ $# -lt 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 2
fi

TENANT="${1}"
ENVIRONMENT="${2}"
MODULE="${3:-}"

UTILS_DIR="deployments/utils/utils.sh"
ENVS_DIR="deployments/utils/envs.sh"

SCRIPT_ABS_PATH="$( realpath "${0}")"
LIB_DIR="${SCRIPT_ABS_PATH%/*}/${TENANT}/envs/${ENVIRONMENT}"

# Load shared helpers (permissive — warn but don't abort if helpers are missing,
# so the script keeps working even when invoked standalone).
if [ -e "${UTILS_DIR}" ]; then
    source "${UTILS_DIR}"
else
    echo "WARN: '${UTILS_DIR}' does not exist; logging helpers will be unavailable."
fi

if [ -e "${ENVS_DIR}" ]; then
    source "${ENVS_DIR}" "${ENVIRONMENT}"
else
    echo "WARN: '${ENVS_DIR}' does not exist; baseline env-vars will not be exported."
fi

# Tenant env-vars dir is mandatory — the wrapper has nothing to do without it.
if [[ ! -d "${LIB_DIR}" ]]; then
  echo "ERROR: tenant env-vars directory not found: ${LIB_DIR}" >&2
  echo "       expected: deployments/on-prem/${TENANT}/envs/${ENVIRONMENT}/*.bash" >&2
  exit 3
fi

shopt -s nullglob
LIB_FILES=( "${LIB_DIR}"/*.bash )
shopt -u nullglob

if [[ ${#LIB_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no *.bash files in ${LIB_DIR} — did you copy *.bash.example to *.bash and fill it in?" >&2
  exit 3
fi

for LIB_FILE in "${LIB_FILES[@]}"; do
  source "${LIB_FILE}" "${ENVIRONMENT}" || { log_info "$(date -u) - FATAL - failure occured while reading ${LIB_FILE}"; exit 1; }
done

# LOCATION is set by deploy-env.bash (defaults to "on-prem"); allow override
LOCATION="${LOCATION:-on-prem}"

INIT_LOG_FILE_NAME="${4:-init-${ENVIRONMENT}.log}"
VALIDATE_LOG_FILE_NAME="${5:-validate-${ENVIRONMENT}.log}"
PLAN_LOG_FILE_NAME="${6:-plan-${ENVIRONMENT}.log}"

if [[ -n "${MODULE}" ]]; then
  cd "${LOCATION}/${TENANT}/${ENVIRONMENT}/${MODULE}"

  terragrunt init     -upgrade -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-init.log
  terragrunt validate          -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-validate.log
  terragrunt plan              -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-plan.log
else
  cd "${LOCATION}/${TENANT}/${ENVIRONMENT}"

  terragrunt run-all init     -upgrade -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-init.log
  terragrunt run-all validate          -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-validate.log
  terragrunt run-all plan              -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-plan.log
fi

log_path=/tmp/terragrunt
mkdir -p "$log_path"
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-init.log     >> "$log_path/${INIT_LOG_FILE_NAME}"
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-validate.log >> "$log_path/${VALIDATE_LOG_FILE_NAME}"
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-plan.log     >> "$log_path/${PLAN_LOG_FILE_NAME}"
