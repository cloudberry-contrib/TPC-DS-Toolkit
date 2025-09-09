#!/bin/bash
set -e

VARS_FILE="tpcds_variables.sh"
FUNCTIONS_FILE="functions.sh"

# shellcheck source=tpcds_variables.sh
source ./${VARS_FILE}
# shellcheck source=functions.sh
source ./${FUNCTIONS_FILE}

TPC_DS_DIR=$(get_pwd ${BASH_SOURCE[0]})
export TPC_DS_DIR

log_time "TPC-DS test started"
printf "\n"

log_time "TPC-DS toolkit version is: V1.5"

# Check that pertinent variables are set in the variable file.
check_variables
# Make sure this is being run as gpadmin
check_admin_user
# Output admin user and multi-user count to standard out
print_header
# Output the version of the database
get_version
export DB_VERSION=${VERSION}
export DB_VERSION_FULL=${VERSION_FULL}
log_time "Current database is:\n${DB_VERSION}"
log_time "Current database version is:\n${DB_VERSION_FULL}"

if [ "${DB_VERSION}" == "postgresql" ]; then
  export RUN_MODEL="cloud"
fi

if [ "${RUN_MODEL}" != "cloud" ]; then
  source_bashrc
fi
# run the benchmark
./rollout.sh
