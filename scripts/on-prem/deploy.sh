# ---------------------------------------------------------------------------------------------------------------------
# RUN TERRAGRUNT PLAN-ALL, OUTPUT THE PLAN TO THE TERMINAL AND TO A LOG FILE
# ---------------------------------------------------------------------------------------------------------------------

#!/usr/bin/env bash
set -euo pipefail

export ENVIRONMENT=${1}
export LOCATION=${2}
export CLUSTER_HOST=${3}
export CLUSTER_CLIENT_KEY=${4}
export CLUSTER_CLIENT_CRT=${5}
export CLUSTER_CLIENT_CA_CRT=${6}
export SERVER_TOKEN=${7}

export JENKINS_USERNAME=${8}
export JENKINS_PASSWORD=${9}


APPLY_LOG_FILE_NAME=${10:-apply-${ENVIRONMENT}.log}

# Run plan all and display output both to terminal and the log file temp.log
cd ${LOCATION}/${ENVIRONMENT}

terragrunt run-all apply -auto-approve -no-color --terragrunt-non-interactive --terragrunt-include-external-dependencies 2>&1 | tee apply.log

sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" apply.log >> ${APPLY_LOG_FILE_NAME}
