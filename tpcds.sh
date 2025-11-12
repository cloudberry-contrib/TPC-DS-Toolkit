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

log_time "TPC-DS toolkit version is: V1.11_dev20251112"

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

if [ "${DB_CURRENT_USER}" != "${BENCH_ROLE}" ]; then
  if [ "${BENCH_ROLE}" == "gpadmin" ]; then
    log_time "Cannot use gpadmin as bench role if not connected as gpadmin."
    exit 1
  fi
fi

if [ "${DB_VERSION}" == "postgresql" ]; then
  export RUN_MODEL="cloud"
fi

if [ "${RUN_MODEL}" != "cloud" ]; then
  source_bashrc
fi

# Backup the log folder before running the benchmark
LOG_FOLDER=${TPC_DS_DIR}/log
LOG_FOLDER_BACKUP=${LOG_FOLDER}_backup_$(date +%Y%m%d_%H%M%S)
cp -r ${LOG_FOLDER} ${LOG_FOLDER_BACKUP}
log_time "Log folder backed up to ${LOG_FOLDER_BACKUP}"

# run the benchmark
./rollout.sh
