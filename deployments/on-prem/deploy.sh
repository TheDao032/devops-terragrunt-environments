#!/usr/bin/env bash

# ---------------------------------------------------------------------------------------------------------------------
# RUN TERRAGRUNT PLAN-ALL, OUTPUT THE PLAN TO THE TERMINAL AND TO A LOG FILE
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

ENVIRONMENT=${1:-"local"}
MODULE=${2:-""}

UTILS_DIR="deployments/utils/utils.sh"

SCRIPT_ABS_PATH="$( realpath "${0}")"
LIB_DIR="${SCRIPT_ABS_PATH%/*}/envs/${ENVIRONMENT}"
# LIB_DIR="deployments/${LOCATION}/envs/${ENVIRONMENT}"

for LIB_FILE in "${LIB_DIR}"/*.bash; do
  source "${UTILS_DIR}"
  source "${LIB_FILE}" ${ENVIRONMENT} || { log_info "$(date -u) - FATAL - failure occured while reading ${LIB_FILE}"; exit 1; }
done

APPLY_LOG_FILE_NAME=${3:-"init-${ENVIRONMENT}.log"}

if [[ -n "${MODULE}" ]]; then
  cd ${LOCATION}/${ENVIRONMENT}/${MODULE}

  terragrunt apply -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-apply.log
else
  # Run apply all and display output both to terminal and the log file temp.log
  cd ${LOCATION}/${ENVIRONMENT}

  terragrunt run-all apply -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-apply.log
fi

log_path=/tmp/terragrunt
mkdir -p $log_path
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-apply.log >> $log_path/${APPLY_LOG_FILE_NAME}
