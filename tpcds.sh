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

if [ "${RUN_MODEL}" != "local" ]; then
  IFS=' ' read -ra GEN_PATHS <<< "${CLIENT_GEN_PATH}"
  
  TOTAL_PATHS=${#GEN_PATHS[@]}
  if [ ${TOTAL_PATHS} -eq 0 ]; then
    log_time "ERROR: CLIENT_GEN_PATH is empty or not set"
    exit 1
  fi
  # Check for duplicate directories in CLIENT_GEN_PATH and remove them
  log_time "Checking for duplicate directories in CLIENT_GEN_PATH..."
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
      log_time "Warning: Duplicate directory found and will be removed: $path"
    fi
  done
  
  if [ "$duplicates_found" = true ]; then
    log_time "Duplicate directories removed. Using unique paths only."
  fi
  GEN_PATHS=("${UNIQUE_GEN_PATHS[@]}")
  
  # Reconstruct the path string and export
  CLIENT_GEN_PATH=$(IFS=' '; echo "${GEN_PATHS[*]}")
  export CLIENT_GEN_PATH
  log_time "CLIENT_GEN_PATH set to: ${CLIENT_GEN_PATH}"
fi

# Get a random port for gpfdist
get_gpfdist_port
log_time "gpfdist port set to: ${GPFDIST_PORT}"

# run the benchmark
./rollout.sh
