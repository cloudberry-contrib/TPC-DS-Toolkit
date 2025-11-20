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
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "kill any orphaned dsdgen processes on segment hosts"
  fi
  # always return true even if no processes were killed
  for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
    ssh ${i} "pkill dsdgen" || true &
  done
  wait
}

function copy_generate_data() {
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "RUN_MODEL is LOCAL, proceeding with copying binaries"
    log_time "copy tpcds binaries and generate_data.sh to segment hosts"
  fi
  # Temporarily disable error exit to capture SSH failures
  set +e  
  local ssh_failed=0
  for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
    scp ${TPC_DS_DIR}/01_gen_data/generate_data.sh ${TPC_DS_DIR}/00_compile_tpcds/tools/dsdgen ${TPC_DS_DIR}/00_compile_tpcds/tools/tpcds.idx ${i}: &
    if [ $? -ne 0 ]; then
     log_time "Error: Failed to copy data generation binaries to host ${i}"
     ssh_failed=1
    fi
  done
  wait
  # Restore error exit
  set -e
  # If any SSH connection failed, exit the program
  if [ $ssh_failed -eq 1 ]; then
    log_time "[ERROR] Failed to connect to some segment hosts. Exiting."
    log_time "Some segment hosts are not reachable, check network connection or try CLOUD mode."
    exit 1
  fi
}

function gen_data() {
  if [ "${USING_CUSTOM_GEN_PATH_IN_LOCAL_MODE}" != "true" ]; then
    log_time "Using default setting as segment data path in local mode on segments."

    TOTAL_PRIMARY=$(gpstate | grep "Total primary segments" | awk -F '=' '{print $2}')
    if [ "${TOTAL_PRIMARY}" == "" ]; then 
      log_time "ERROR: Unable to determine how many primary segments are in the cluster using gpstate."
      exit 1
    fi

    if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then
      SQL_QUERY="select row_number() over(), g.hostname, p.fselocation as path from gp_segment_configuration g join pg_filespace_entry p on g.dbid = p.fsedbid join pg_tablespace t on t.spcfsoid = p.fsefsoid where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' and t.spcname = 'pg_default' order by 1, 2, 3"  
    else
      SQL_QUERY="select row_number() over(), g.hostname, g.datadir from gp_segment_configuration g where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' order by 1, 2, 3"
    
    fi

    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Number of primary segments: ${TOTAL_PRIMARY}"
    fi
    # Calculate total parallel processes
    # Each path gets GEN_DATA_PARALLEL processes per host
    PARALLEL=$((TOTAL_PRIMARY * GEN_DATA_PARALLEL))
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Total parallel processes: ${PARALLEL} (primary segments: ${TOTAL_PRIMARY} * parallel_per_path: ${GEN_DATA_PARALLEL})"
      log_time "Clean up previous data generation folder on segments."
    fi 
    
    for h in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
      EXT_HOST=$(echo ${h} | awk -F '|' '{print $2}')
      SEG_DATA_PATH=$(echo ${h} | awk -F '|' '{print $3}' | sed 's#//#/#g')
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "ssh -n ${EXT_HOST} \"rm -rf ${SEG_DATA_PATH}/dsbenchmark; mkdir -p ${SEG_DATA_PATH}/dsbenchmark/logs\" &"
      fi
      ssh -n ${EXT_HOST} "rm -rf ${SEG_DATA_PATH}/dsbenchmark; mkdir -p ${SEG_DATA_PATH}/dsbenchmark/logs" &
    done
    wait 
    
    CHILD=1
    for i in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
      EXT_HOST=$(echo ${i} | awk -F '|' '{print $2}')
      SEG_DATA_PATH=$(echo ${i} | awk -F '|' '{print $3}' | sed 's#//#/#g')
  
      for ((j=1; j<=GEN_DATA_PARALLEL; j++)); do
        GEN_DATA_PATH="${SEG_DATA_PATH}/dsbenchmark/${CHILD}"
        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "ssh -n ${EXT_HOST} \"bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_PATH} ${RNGSEED} > ${SEG_DATA_PATH}/dsbenchmark/logs/tpcds.generate_data.${CHILD}.log 2>&1 &'\""
        fi
        ssh -n ${EXT_HOST} "bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_PATH} ${RNGSEED} > ${SEG_DATA_PATH}/dsbenchmark/logs/tpcds.generate_data.${CHILD}.log 2>&1 &'" &
        CHILD=$((CHILD + 1))
      done
    done
  else
    log_time "Using CUSTOM_GEN_PATH in local mode on segments."
    
    IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
    TOTAL_PATHS=${#GEN_PATHS[@]}
    
    if [ ${TOTAL_PATHS} -eq 0 ]; then
      log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
      exit 1
    fi
    
    TOTAL_HOSTS=$(wc -l < ${TPC_DS_DIR}/segment_hosts.txt)


    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Number of segment hosts: ${TOTAL_HOSTS}"
      log_time "Number of data generation paths: ${TOTAL_PATHS}"
    fi

    # Calculate total parallel processes
    # Each path gets GEN_DATA_PARALLEL processes per host
    PARALLEL=$((TOTAL_PATHS * GEN_DATA_PARALLEL * TOTAL_HOSTS))
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Total parallel processes: ${PARALLEL} (paths: ${TOTAL_PATHS} * parallel_per_path: ${GEN_DATA_PARALLEL} * hosts: ${TOTAL_HOSTS})"
      log_time "Clean up and prepare data generation folders on segments."
    fi
    for EXT_HOST in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
      # Clean up existing directories and create new ones
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "ssh -n ${EXT_HOST} \"rm -rf ${GEN_DATA_PATH}/dsbenchmark; mkdir -p ${GEN_DATA_PATH}/dsbenchmark/logs\" &"
        fi
        ssh -n ${EXT_HOST} "rm -rf ${GEN_DATA_PATH}/dsbenchmark; mkdir -p ${GEN_DATA_PATH}/dsbenchmark/logs" &
      done
    done
    wait
    
    # Start data generation on each segment host
    log_time "Starting data generation on segment hosts."
    CHILD=1
    for EXT_HOST in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
      # For each path, start GEN_DATA_PARALLEL processes
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        for ((j=1; j<=GEN_DATA_PARALLEL; j++)); do
          GEN_DATA_SUBPATH="${GEN_DATA_PATH}/dsbenchmark/${CHILD}"
          if [ "${LOG_DEBUG}" == "true" ]; then
            log_time "ssh -n ${EXT_HOST} \"bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_SUBPATH} ${RNGSEED} > ${GEN_DATA_PATH}/dsbenchmark/logs/tpcds.generate.data.${CHILD}.log 2>&1 &'\""
          fi
          ssh -n ${EXT_HOST} "bash -c 'cd ~/; ./generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_SUBPATH} ${RNGSEED} > ${GEN_DATA_PATH}/dsbenchmark/logs/tpcds.generate.data.${CHILD}.log 2>&1 &'" &
          CHILD=$((CHILD + 1))
        done
      done
    done
  fi
}

step="gen_data"

log_time "Step ${step} started"

init_log ${step}
start_log
schema_name="${DB_VERSION}"
export schema_name
table_name="gen_data"
export table_name

if [ "${GEN_NEW_DATA}" == "true" ]; then
  log_time "Start generating data with RUN_MODEL ${RUN_MODEL} with GEN_DATA_SCALE ${GEN_DATA_SCALE}."
  SECONDS=0

  if [ "${RUN_MODEL}" != "local" ]; then      
    # Split CUSTOM_GEN_PATH into array of paths
    IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
    TOTAL_PATHS=${#GEN_PATHS[@]}
    
    if [ ${TOTAL_PATHS} -eq 0 ]; then
      log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
      exit 1
    fi
    
    PARALLEL=$((TOTAL_PATHS * GEN_DATA_PARALLEL))
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Number of data generation paths: ${TOTAL_PATHS}"
      log_time "Parallel processes per path: ${GEN_DATA_PARALLEL}"
      log_time "Total parallel processes: ${PARALLEL}"
    fi
    # Prepare each data generation path
    for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
      if [[ ! -d "${GEN_DATA_PATH}" && ! -L "${GEN_DATA_PATH}" ]]; then
        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "mkdir ${GEN_DATA_PATH}/dsbenchmark"
        fi
        mkdir -p ${GEN_DATA_PATH}/dsbenchmark
      fi
      rm -rf ${GEN_DATA_PATH}/dsbenchmark/*
      mkdir -p ${GEN_DATA_PATH}/dsbenchmark/logs
    done
      
    CHILD=1
    for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
      for ((j=1; j<=GEN_DATA_PARALLEL; j++)); do
        GEN_DATA_SUBPATH="${GEN_DATA_PATH}/dsbenchmark/${CHILD}"
        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "sh ${TPC_DS_DIR}/01_gen_data/generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_SUBPATH} ${RNGSEED} > ${GEN_DATA_PATH}/dsbenchmark/logs/tpcds.generate.data.${CHILD}.log 2>&1 &"
        fi
        sh ${TPC_DS_DIR}/01_gen_data/generate_data.sh ${GEN_DATA_SCALE} ${CHILD} ${PARALLEL} ${GEN_DATA_SUBPATH} ${RNGSEED} > ${GEN_DATA_PATH}/dsbenchmark/logs/tpcds.generate.data.${CHILD}.log 2>&1 &
        CHILD=$((CHILD + 1))
      done
    done
    log_time "Now generating data...This may take a while."
    count=$(ps -ef |grep -v grep |grep "generate_data.sh"|wc -l || true)
    seconds=0
    echo -ne "Generating data duration: "
    while [ "$count" -gt "0" ]; do
      printf "\rGenerating data duration: ${seconds} second(s)"
      sleep 5
      seconds=$((seconds + 5))
      count=$(ps -ef |grep -v grep |grep "generate_data.sh"|wc -l || true)
    done
  else
    kill_orphaned_data_gen
    copy_generate_data
    gen_data
    log_time "Now generating data...This may take a while."
    count=$(get_count_generate_data)
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
  log_time "Data generation completed on all segment hosts in ${SECONDS} second(s)."
  log_time "Done generating data"
fi

print_log

log_time "Step ${step} finished"
printf "\n"