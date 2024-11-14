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

for LIB_FILE in "${LIB_DIR}"/*.bash; do
  source "${UTILS_DIR}"
  source "${LIB_FILE}" ${ENVIRONMENT} || { log_info "$(date -u) - FATAL - failure occured while reading ${LIB_FILE}"; exit 1; }
done

INIT_LOG_FILE_NAME=${3:-"init-${ENVIRONMENT}.log"}
VALIDATE_LOG_FILE_NAME=${4:-"validate-${ENVIRONMENT}.log"}
PLAN_LOG_FILE_NAME=${5:-"plan-${ENVIRONMENT}.log"}

if [[ -n "${MODULE}" ]]; then
  cd ${LOCATION}/${ENVIRONMENT}/${MODULE}

  terragrunt init -upgrade -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies --terragrunt-debug 2>&1 | tee /tmp/terragrunt-init.log
  terragrunt validate -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies --terragrunt-debug 2>&1 | tee /tmp/terragrunt-validate.log
  terragrunt plan -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies --terragrunt-debug 2>&1 | tee /tmp/terragrunt-plan.log
else
  # Run plan all and display output both to terminal and the log file temp.log
  cd ${LOCATION}/${ENVIRONMENT}

  terragrunt run-all init -upgrade -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-init.log
  terragrunt run-all validate -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-validate.log
  terragrunt run-all plan -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee /tmp/terragrunt-plan.log
fi

log_path=/tmp/terragrunt
mkdir -p $log_path
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-init.log >> $log_path/${INIT_LOG_FILE_NAME}
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-validate.log >> $log_path/${VALIDATE_LOG_FILE_NAME}
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/terragrunt-plan.log >> $log_path/${PLAN_LOG_FILE_NAME}
