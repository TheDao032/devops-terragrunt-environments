# ---------------------------------------------------------------------------------------------------------------------
# RUN TERRAGRUNT PLAN-ALL, OUTPUT THE PLAN TO THE TERMINAL AND TO A LOG FILE
# ---------------------------------------------------------------------------------------------------------------------

#!/usr/bin/env bash
set -euo pipefail

export ENVIRONMENT=${1}
export LOCATION=${2}
export KUBE_HOST=${3}
export KUBE_CLIENT_KEY=${4}
export KUBE_CLIENT_CRT=${5}
export KUBE_CLIENT_CA_CRT=${6}
export KUBE_TOKEN=${7}

export JENKINS_PASSWORD=${8}

DESTROY_LOG_FILE_NAME=${9:-destroy-${ENVIRONMENT}.log}

# Run deploy all and display output both to terminal and the log file temp.log
cd ${LOCATION}/${ENVIRONMENT}

terragrunt run-all destroy -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee destroy.log

sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" destroy.log >> ${DESTROY_LOG_FILE_NAME}
