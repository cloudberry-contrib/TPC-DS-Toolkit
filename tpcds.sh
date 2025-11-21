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
log_time "TPC-DS toolkit version is: V2.2"

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
log_time "Current database is: ${DB_VERSION}"
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

if [ "${RUN_MODEL}" != "local" ]; then
  export CUSTOM_GEN_PATH="$(echo "${CUSTOM_GEN_PATH}" | tr '[:upper:]' '[:lower:]')"

  IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
  
  TOTAL_PATHS=${#GEN_PATHS[@]}
  if [ ${TOTAL_PATHS} -eq 0 ]; then
    log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
    exit 1
  fi
  # Check for duplicate directories in CUSTOM_GEN_PATH and remove them
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Checking for duplicate directories in CUSTOM_GEN_PATH..."
  fi
  # Using string method instead of associative array for better compatibility
  declare -a UNIQUE_GEN_PATHS
  duplicates_found=false
  
  for path in "${GEN_PATHS[@]}"; do
    # Check if path is already in the unique paths array (compatible with all Bash versions)
    is_duplicate=false
    for unique_path in "${UNIQUE_GEN_PATHS[@]}"; do
      if [ "$unique_path" = "$path" ]; then
        is_duplicate=true
        break
      fi
    done
    
    if [ "$is_duplicate" = false ]; then
      # Add path to unique paths array
      UNIQUE_GEN_PATHS+=("$path")
    else
      duplicates_found=true
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "Warning: Duplicate directory found and will be removed: $path"
      fi
    fi
  done
  
  if [ "$duplicates_found" = true ]; then
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Duplicate directories removed. Using unique paths only."
    fi
  fi
  GEN_PATHS=("${UNIQUE_GEN_PATHS[@]}")
  
  # Reconstruct the path string and export
  CUSTOM_GEN_PATH=$(IFS=' '; echo "${GEN_PATHS[*]}")
  export CUSTOM_GEN_PATH
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "CUSTOM_GEN_PATH set to: ${CUSTOM_GEN_PATH}"
  fi
else
  create_hosts_file
fi

# Get a random port for gpfdist
get_gpfdist_port
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "gpfdist port set to: ${GPFDIST_PORT}"
fi
echo ""

# run the benchmark
./rollout.sh
