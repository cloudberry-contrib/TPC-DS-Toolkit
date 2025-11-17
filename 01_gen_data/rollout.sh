#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

if [ "${GEN_DATA_SCALE}" == "" ]; then
  log_time "You must provide the scale as a parameter in terms of Gigabytes."
  log_time "Example: ./rollout.sh 100"
  log_time "This will create 100 GB of data for this test."
  exit 1
fi

# Handle RNGSEED configuration
if [ "${UNIFY_QGEN_SEED}" == "true" ]; then
  # Use a fixed RNGSEED when unified seed is enabled
  RNGSEED=2016032410
else 
  # Get a random RNGSEED from current time
  RNGSEED=$(date +%s)
fi

function get_count_generate_data() {
  # Initialize counter as integer type
  local count=0
  
  # Check if segment_hosts.txt file exists
  if [ ! -f "${TPC_DS_DIR}/segment_hosts.txt" ]; then
    log_time "ERROR: segment_hosts.txt not found at ${TPC_DS_DIR}"
    return 0
  fi
  
  while read -r i; do
    # Set reasonable connection timeout to avoid infinite waiting
    # Use -n option instead of -f to ensure command completes
    next_count=$(ssh -o ConnectTimeout=10 -o LogLevel=quiet -n ${i} "bash -c 'ps -ef | grep generate_data.sh | grep -v grep | wc -l'" 2>/dev/null)
    
    # Check if it's a valid number, default to 0 if not
    check="^[0-9]+$"
    if ! [[ "${next_count}" =~ ${check} ]]; then
      log_time "WARNING: Failed to get process count from host ${i}, assuming 0"
      next_count=0
    fi
    
    count=$((count + next_count))
  done < "${TPC_DS_DIR}/segment_hosts.txt"
  
  # Return calculated result
  echo "${count}"
  return 0
}

function kill_orphaned_data_gen() {
  log_time "kill any orphaned dsdgen processes on segment hosts"
  # always return true even if no processes were killed
  for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
    ssh ${i} "pkill dsdgen" || true &
    ssh ${i} "rm -rf /tmp/tpcds.generate_data.*.log" || true &
  done
  wait
}

function copy_generate_data() {
  log_time "copy generate_data.sh to segment hosts"
  for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
    scp ${PWD}/generate_data.sh ${i}: &
  done
  wait
}

function gen_data() {
  if [ "${USING_CUSTOM_GEN_PATH_IN_LOCAL_MODE}" != "true" ]; then
    log_time "Using default setting as segment data path in local mode on segments."

    PARALLEL=$(gpstate | grep "Total primary segments" | awk -F '=' '{print $2}')
    if [ "${PARALLEL}" == "" ]; then
      log_time "ERROR: Unable to determine how many primary segments are in the cluster using gpstate."
      exit 1
    fi
  
    #Actual PARALLEL should be $GEN_DATA_PARALLEL*$PARALLEL
    PARALLEL=$((GEN_DATA_PARALLEL * PARALLEL))
    
    log_time "Number of Generate Data Parallel Process is: $PARALLEL"
  
    
    if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then
      SQL_QUERY="select row_number() over(), g.hostname, p.fselocation as path from gp_segment_configuration g join pg_filespace_entry p on g.dbid = p.fsedbid join pg_tablespace t on t.spcfsoid = p.fsefsoid where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' and t.spcname = 'pg_default' order by 1, 2, 3"  
    else
      SQL_QUERY="select row_number() over(), g.hostname, g.datadir from gp_segment_configuration g where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' order by 1, 2, 3"
    
    fi
    
    log_time "Clean up previous data generation folder on segments."
    for h in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
      EXT_HOST=$(echo ${h} | awk -F '|' '{print $2}')
      SEG_DATA_PATH=$(echo ${h} | awk -F '|' '{print $3}' | sed 's#//#/#g')
      log_time "ssh -n ${EXT_HOST} \"rm -rf ${SEG_DATA_PATH}/dsbenchmark\""
      ssh -n ${EXT_HOST} "rm -rf ${SEG_DATA_PATH}/dsbenchmark"
      log_time "ssh -n ${EXT_HOST} \"mkdir -p ${SEG_DATA_PATH}/dsbenchmark\""
      ssh -n ${EXT_HOST} "mkdir -p ${SEG_DATA_PATH}/dsbenchmark"
    done
    
    CHILD=1
    for i in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
      EXT_HOST=$(echo ${i} | awk -F '|' '{print $2}')
      SEG_DATA_PATH=$(echo ${i} | awk -F '|' '{print $3}' | sed 's#//#/#g')
  
      for ((j=1; j<=GEN_DATA_PARALLEL; j++)); do
        GEN_DATA_PATH="${SEG_DATA_PATH}/dsbenchmark/${CHILD}"
        log_time "ssh -n ${EXT_HOST} \"bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_PATH} ${RNGSEED} > /tmp/tpcds.generate_data.${CHILD}.log 2>&1 &'\""
        ssh -n ${EXT_HOST} "bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_PATH} ${RNGSEED} > /tmp/tpcds.generate_data.${CHILD}.log 2>&1 &'" &
        CHILD=$((CHILD + 1))
      done
    done
    wait
  else
    log_time "Using CUSTOM_GEN_PATH in local mode on segments."
    
    # Get segment hosts from database
    if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then
      SQL_QUERY="select distinct g.hostname from gp_segment_configuration g join pg_filespace_entry p on g.dbid = p.fsedbid join pg_tablespace t on t.spcfsoid = p.fsefsoid where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' and t.spcname = 'pg_default' order by 1"
    else
      SQL_QUERY="select distinct g.hostname from gp_segment_configuration g where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' order by 1"
    fi
    
    # Generate segment hosts file
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}" > ${TPC_DS_DIR}/segment_hosts.txt
    
    # Split CUSTOM_GEN_PATH into array of paths
    IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
    TOTAL_PATHS=${#GEN_PATHS[@]}
    
    if [ ${TOTAL_PATHS} -eq 0 ]; then
      log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
      exit 1
    fi
    
    # Get number of segment hosts
    SEGMENT_HOSTS_COUNT=$(wc -l < ${TPC_DS_DIR}/segment_hosts.txt)
    if [ ${SEGMENT_HOSTS_COUNT} -eq 0 ]; then
      log_time "ERROR: No segment hosts found"
      exit 1
    fi
    
    log_time "Number of segment hosts: ${SEGMENT_HOSTS_COUNT}"
    log_time "Number of data generation paths: ${TOTAL_PATHS}"
    log_time "CUSTOM_GEN_PATH: ${CUSTOM_GEN_PATH}"
    
    # Calculate total parallel processes
    # Each path gets GEN_DATA_PARALLEL processes per host
    PARALLEL=$((TOTAL_PATHS * GEN_DATA_PARALLEL * SEGMENT_HOSTS_COUNT))
    log_time "Total parallel processes: ${PARALLEL} (paths: ${TOTAL_PATHS} * parallel_per_path: ${GEN_DATA_PARALLEL} * hosts: ${SEGMENT_HOSTS_COUNT})"
    
    # Copy generate_data.sh to all segment hosts
    copy_generate_data
    
    # Clean up and prepare directories on each segment host
    log_time "Clean up and prepare data generation folders on segments."
    HOST_INDEX=0
    while read -r HOST; do
      if [ -z "${HOST}" ]; then
        continue
      fi
      
      # Clean up existing directories and create new ones
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        log_time "ssh -n ${HOST} \"rm -rf ${GEN_DATA_PATH}/dsbenchmark\""
        ssh -n ${HOST} "rm -rf ${GEN_DATA_PATH}/dsbenchmark"
        log_time "ssh -n ${HOST} \"mkdir -p ${GEN_DATA_PATH}/dsbenchmark\""
        ssh -n ${HOST} "mkdir -p ${GEN_DATA_PATH}/dsbenchmark"
      done
      
      HOST_INDEX=$((HOST_INDEX + 1))
    done < ${TPC_DS_DIR}/segment_hosts.txt
    
    # Start data generation on each segment host
    log_time "Starting data generation on segment hosts."
    GLOBAL_CHILD=1
    HOST_INDEX=0
    while read -r HOST; do
      if [ -z "${HOST}" ]; then
        continue
      fi
      
      log_time "Starting data generation on host: ${HOST}"
      
      # For each path, start GEN_DATA_PARALLEL processes
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        for ((j=1; j<=GEN_DATA_PARALLEL; j++)); do
          GEN_DATA_SUBPATH="${GEN_DATA_PATH}/dsbenchmark/${GLOBAL_CHILD}"
          log_time "ssh -n ${HOST} \"bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${GLOBAL_CHILD} ${PARALLEL} ${GEN_DATA_SUBPATH} ${RNGSEED} > /tmp/tpcds.generate_data.${GLOBAL_CHILD}.log 2>&1 &'\""
          ssh -n ${HOST} "bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${GLOBAL_CHILD} ${PARALLEL} ${GEN_DATA_SUBPATH} ${RNGSEED} > /tmp/tpcds.generate.data.${GLOBAL_CHILD}.log 2>&1 &'" &
          GLOBAL_CHILD=$((GLOBAL_CHILD + 1))
        done
      done
      
      HOST_INDEX=$((HOST_INDEX + 1))
    done < ${TPC_DS_DIR}/segment_hosts.txt
    
    wait
    log_time "Data generation completed on all segment hosts."
  fi
}

step="gen_data"

log_time "Step ${step} started"
printf "\n"

init_log ${step}
start_log
schema_name="${DB_VERSION}"
export schema_name
table_name="gen_data"
export table_name

if [ "${GEN_NEW_DATA}" == "true" ]; then
    if [ "${RUN_MODEL}" != "local" ]; then
      PARALLEL=${GEN_DATA_PARALLEL}
      
      # Split CUSTOM_GEN_PATH into array of paths
      IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
      TOTAL_PATHS=${#GEN_PATHS[@]}
      
      if [ ${TOTAL_PATHS} -eq 0 ]; then
        log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
        exit 1
      fi
      
      log_time "Number of data generation paths: ${TOTAL_PATHS}"
      log_time "Parallel processes per path: ${PARALLEL}"
      log_time "Total parallel processes: $((TOTAL_PATHS * PARALLEL))"
      
      # Prepare each data generation path
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        if [[ ! -d "${GEN_DATA_PATH}" && ! -L "${GEN_DATA_PATH}" ]]; then
          log_time "mkdir ${GEN_DATA_PATH}"
          mkdir -p ${GEN_DATA_PATH}
        fi
        rm -rf ${GEN_DATA_PATH}/*
        mkdir -p ${GEN_DATA_PATH}/logs
      done
      
      # Start data generation processes for each path
      TOTAL_PARALLEL=$((TOTAL_PATHS * PARALLEL))
      CHILD=1
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        # Save the starting CHILD number for current path
        CURRENT_START_CHILD=${CHILD}
        PATH_CHILD=1
        while [ ${PATH_CHILD} -le ${PARALLEL} ]; do
          log_time "sh ${PWD}/dsdgen -scale ${GEN_DATA_SCALE} -dir ${GEN_DATA_PATH} -parallel ${TOTAL_PARALLEL} -child ${CHILD} -RNGSEED ${RNGSEED} -terminate n > ${GEN_DATA_PATH}/logs/tpcds.generate_data.${CHILD}.log 2>&1 &"
          cd ${PWD}
          ${PWD}/dsdgen -scale ${GEN_DATA_SCALE} -dir ${GEN_DATA_PATH} -parallel ${TOTAL_PARALLEL} -child ${CHILD} -RNGSEED ${RNGSEED} -terminate n > ${GEN_DATA_PATH}/logs/tpcds.generate_data.${CHILD}.log 2>&1 &
          PATH_CHILD=$((PATH_CHILD + 1))
          CHILD=$((CHILD + 1))
        done
      done
        # Wait for data generation processes in current path to complete
      log_time "Waiting for data generation processes to complete..."
      wait
      
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        # make sure there is a file in each directory so that gpfdist doesn't throw an error
        declare -a tables=("call_center" "catalog_page" "catalog_returns" "catalog_sales" "customer" "customer_address" "customer_demographics" "date_dim" "household_demographics" "income_band" "inventory" "item" "promotion" "reason" "ship_mode" "store" "store_returns" "store_sales" "time_dim" "warehouse" "web_page" "web_returns" "web_sales" "web_site")

        # Create empty files with correct directory path and CHILD numbers
        for i in "${tables[@]}"; do
          # Create files for each CHILD number in current path
          # Check if any file matching the pattern exists
          filename_pattern="${GEN_DATA_PATH}/${i}_[0-9]*_[0-9]*.dat"
          log_time "Checking if files exist: ${filename_pattern}"
          
          # Simple file check using ls and grep
          # If no matching files found, create a placeholder file
          if ! ls ${filename_pattern} 2>/dev/null | grep -q .; then
            placeholder_file="${GEN_DATA_PATH}/${i}_0_0.dat"
            log_time "Creating placeholder file: ${placeholder_file}"
            touch "${placeholder_file}"
          fi
        done
      done
    else
    kill_orphaned_data_gen
    copy_generate_data
    gen_data
    echo ""
    count=$(get_count_generate_data)
    log_time "Now generating data.  This may take a while."
    seconds=0
    echo -ne "Generating data duration: "
    while [ "$count" -gt "0" ]; do
      printf "\rGenerating data duration: ${seconds} second(s)"
      sleep 5
      seconds=$((seconds + 5))
      count=$(get_count_generate_data)
    done
  fi
  echo ""
  log_time "Done generating data"
fi

print_log

log_time "Step ${step} finished"
printf "\n"