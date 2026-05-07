#!/usr/bin/env bash

# ---------------------------------------------------------------------------------------------------------------------
# Run terragrunt destroy for a tenant + environment under on-prem.
#
# Usage:
#   ./deployments/on-prem/destroy.sh <tenant> <environment> [module]
#
# Examples:
#   ./deployments/on-prem/destroy.sh bosch   local
#   ./deployments/on-prem/destroy.sh renesas dev jenkins
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <tenant> <environment> [module]

  tenant       e.g. bosch | renesas
  environment  e.g. local | dev | stg | prod
  module       (optional) single resource to act on; default = all

Optional positional args (advanced):
  4: DESTROY_LOG_FILE_NAME  (default: destroy-<env>.log)
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

LOCATION="${LOCATION:-on-prem}"
DESTROY_LOG_FILE_NAME="${4:-destroy-${ENVIRONMENT}.log}"

if [[ -n "${MODULE}" ]]; then
  cd "${LOCATION}/${TENANT}/${ENVIRONMENT}/${MODULE}"

  terragrunt destroy -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-destroy.log
else
  cd "${LOCATION}/${TENANT}/${ENVIRONMENT}"

  terragrunt run-all destroy -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-destroy.log
fi

log_path=/tmp/terragrunt
mkdir -p "$log_path"
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-destroy.log >> "$log_path/${DESTROY_LOG_FILE_NAME}"
