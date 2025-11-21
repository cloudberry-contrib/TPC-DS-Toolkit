#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

step="load"

log_time "Step ${step} started"

init_log ${step}

filter="gpdb"

function copy_script() {
  log_time "copy the start and stop scripts to the segment hosts in the cluster"
  for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "scp start_gpfdist.sh stop_gpfdist.sh ${i}:"
    fi
    scp ${PWD}/start_gpfdist.sh ${PWD}/stop_gpfdist.sh ${i}: &
  done
  wait
}

function stop_gpfdist() {
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "stop gpfdist on all ports"
  fi
  for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
    ssh -n $i "bash -c 'cd ~/; ./stop_gpfdist.sh'" &
  done
  wait
}

function start_gpfdist() {
  stop_gpfdist
  sleep 1

  if [ "${USING_CUSTOM_GEN_PATH_IN_LOCAL_MODE}" == "true" ]; then
    # Handle custom CUSTOM_GEN_PATH in local mode
    IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
    
    if [ ${#GEN_PATHS[@]} -eq 0 ]; then
      log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
      exit 1
    fi
    
    flag=10
    for EXT_HOST in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
      # For each path, start a gpfdist instance
      for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
        GEN_DATA_PATH="${GEN_DATA_PATH}/dsbenchmark"
        PORT=$((GPFDIST_PORT + flag))
        let flag=$flag+1
        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "ssh -n ${EXT_HOST} \"bash -c 'cd ~${ADMIN_USER}; ./start_gpfdist.sh $PORT ${GEN_DATA_PATH} ${env_file}'\""
        fi
        ssh -n ${EXT_HOST} "bash -c 'cd ~${ADMIN_USER}; ./start_gpfdist.sh $PORT ${GEN_DATA_PATH} ${env_file}'" &
      done
    done
  else
    # Original logic for default local mode
    if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then
      SQL_QUERY="select rank() over (partition by g.hostname order by p.fselocation), g.hostname, p.fselocation as path from gp_segment_configuration g join pg_filespace_entry p on g.dbid = p.fsedbid join pg_tablespace t on t.spcfsoid = p.fsefsoid where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' and t.spcname = 'pg_default' order by g.hostname"
    else
      SQL_QUERY="select rank() over(partition by g.hostname order by g.datadir), g.hostname, g.datadir from gp_segment_configuration g where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' order by g.hostname"
    fi

    flag=10
    for i in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
      CHILD=$(echo ${i} | awk -F '|' '{print $1}')
      EXT_HOST=$(echo ${i} | awk -F '|' '{print $2}')
      GEN_DATA_PATH=$(echo ${i} | awk -F '|' '{print $3}'| sed 's#//#/#g')
      GEN_DATA_PATH="${GEN_DATA_PATH}/dsbenchmark"
      PORT=$((GPFDIST_PORT + flag))
      let flag=$flag+1
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "ssh -n ${EXT_HOST} \"bash -c 'cd ~${ADMIN_USER}; ./start_gpfdist.sh $PORT ${GEN_DATA_PATH} ${env_file}'\""
      fi
      ssh -n ${EXT_HOST} "bash -c 'cd ~${ADMIN_USER}; ./start_gpfdist.sh $PORT ${GEN_DATA_PATH} ${env_file}'" &
    done
  fi
  wait
}

if [ "${RUN_MODEL}" == "remote" ]; then
  sh ${PWD}/stop_gpfdist.sh
  # Split CUSTOM_GEN_PATH into array of paths to support multiple directories
  IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
  
  if [ ${#GEN_PATHS[@]} -eq 0 ]; then
    log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
    exit 1
  fi

  CLOUDBERRY_BINARY_PATH=${GPHOME}
  env_file=""

  if [ "$DB_VERSION" = "synxdb_4" ]; then
    env_file="${CLOUDBERRY_BINARY_PATH}/cloudberry-env.sh"
  elif [ "$DB_VERSION" = "synxdb_2" ]; then
    env_file="${CLOUDBERRY_BINARY_PATH}/synxdb_path.sh"
  else
    env_file="${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh"
  fi

  if [ ! -f "${env_file}" ]; then
    log_time "Environment file ${env_file} not found, searching for alternative configuration files..."
    
    config_files=("greenplum_path.sh" "cluster_env.sh" "synxdb_path.sh" "cloudberry-env.sh")
    found_config=""
    
    for config in "${config_files[@]}"; do
        if [ -f "${CLOUDBERRY_BINARY_PATH}/${config}" ]; then
            found_config="${config}"
            log_time "Found configuration file: ${CLOUDBERRY_BINARY_PATH}/${config}"
            break
        fi
    done
    
    if [ -n "${found_config}" ]; then
        env_file="${CLOUDBERRY_BINARY_PATH}/${found_config}"
        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "Updated environment file to: ${env_file}"
        fi
    else
        log_time "ERROR: No configuration files found in ${CLOUDBERRY_BINARY_PATH}"
        log_time "Searched for: ${config_files[*]}"
        exit 1
    fi
  else
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Using environment file: ${env_file}"
    fi
  fi
  
  # Start gpfdist for each data path with different ports
  flag=10
  for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
    GEN_DATA_PATH="${GEN_DATA_PATH}/dsbenchmark"
    PORT=$((GPFDIST_PORT + flag))
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Starting gpfdist on port ${PORT} for path: ${GEN_DATA_PATH}"
    fi
    sh ${PWD}/start_gpfdist.sh $PORT "${GEN_DATA_PATH}" ${env_file}
    let flag=$flag+1
  done
  
  # Set GEN_DATA_PATH to the first path for backward compatibility
  GEN_DATA_PATH=${GEN_PATHS[0]}
elif [ "${RUN_MODEL}" == "local" ]; then
  CLOUDBERRY_BINARY_PATH=${GPHOME}
  env_file=""

  if [ "$DB_VERSION" = "synxdb_4" ]; then
    env_file="${CLOUDBERRY_BINARY_PATH}/cloudberry-env.sh"
  elif [ "$DB_VERSION" = "synxdb_2" ]; then
    env_file="${CLOUDBERRY_BINARY_PATH}/synxdb_path.sh"
  else
    env_file="${CLOUDBERRY_BINARY_PATH}/greenplum_path.sh"
  fi

  if [ ! -f "${env_file}" ]; then
    log_time "Environment file ${env_file} not found, searching for alternative configuration files..."
    
    config_files=("greenplum_path.sh" "cluster_env.sh" "synxdb_path.sh" "cloudberry-env.sh")
    found_config=""
    
    for config in "${config_files[@]}"; do
        if [ -f "${CLOUDBERRY_BINARY_PATH}/${config}" ]; then
            found_config="${config}"
            log_time "Found configuration file: ${CLOUDBERRY_BINARY_PATH}/${config}"
            break
        fi
    done
    
    if [ -n "${found_config}" ]; then
        env_file="${CLOUDBERRY_BINARY_PATH}/${found_config}"
        log_time "Updated environment file to: ${env_file}"
    else
        log_time "ERROR: No configuration files found in ${CLOUDBERRY_BINARY_PATH}"
        log_time "Searched for: ${config_files[*]}"
        exit 1
    fi
  else
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Using environment file: ${env_file}"
    fi
  fi
  
  copy_script
  start_gpfdist
fi
# need to wait for all the gpfdist processes to start
# sleep 10

# Create FIFO for concurrency control
mkfifo /tmp/$$.fifo
exec 5<> /tmp/$$.fifo
rm -f /tmp/$$.fifo

# Initialize tokens based on the value of LOAD_PARALLEL
for ((i=0; i<${LOAD_PARALLEL}; i++)); do
    echo >&5
done

log_time "Loading tables in schema ${DB_SCHEMA_NAME} with parallelism ${LOAD_PARALLEL}"
SECONDS=0

# Use find to get just filenames, then process each file in numeric order
for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${filter}.*.sql" -printf "%f\n" | sort -n); do
    # Acquire a token to control concurrency
    read -u 5
    {
        start_log

        id=$(echo "${i}" | awk -F '.' '{print $1}')
        export id
        schema_name=${DB_SCHEMA_NAME}
        export schema_name
        table_name=$(echo "${i}" | awk -F '.' '{print $3}')
        export table_name

        if [ "${TRUNCATE_TABLES}" == "true" ]; then
            if [ "${LOG_DEBUG}" == "true" ]; then
              log_time "Truncate table ${DB_SCHEMA_NAME}.${table_name}"
            fi
            psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -c "TRUNCATE TABLE ${DB_SCHEMA_NAME}.${table_name}"
        fi

        if [ "${LOG_DEBUG}" == "true" ]; then
          log_time "Loading table ${DB_SCHEMA_NAME}.${table_name}"
        fi

        if [ "${RUN_MODEL}" == "cloud" ]; then
            # Split CUSTOM_GEN_PATH into array of paths
            IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
            TOTAL_PATHS=${#GEN_PATHS[@]}
            
            if [ ${TOTAL_PATHS} -eq 0 ]; then
                log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
                exit 1
            fi
            
            tuples=0
            for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
                if [ "${LOG_DEBUG}" == "true" ]; then
                  log_time "Loading data from path: ${GEN_DATA_PATH}"
                fi
                for file in ${GEN_DATA_PATH}/dsbenchmark/[0-9]*/${table_name}_[0-9]*_[0-9]*.dat; do
                  if [ -e "$file" ]; then
                    if [ "${LOG_DEBUG}" == "true" ]; then
                      log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -c \"\COPY ${DB_SCHEMA_NAME}.${table_name} FROM '$file' WITH (FORMAT csv, DELIMITER '|', NULL '', ESCAPE E'\\\\\\\\', ENCODING 'LATIN1')\" | grep COPY | awk -F ' ' '{print \$2}'"
                    fi
                    result=$(
                      psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -c "\COPY ${DB_SCHEMA_NAME}.${table_name} FROM '$file' WITH (FORMAT csv, DELIMITER '|', NULL '', ESCAPE E'\\\\', ENCODING 'LATIN1')" | grep COPY | awk -F ' ' '{print $2}'
                      exit ${PIPESTATUS[0]}
                    )
                    tuples=$((tuples + result))
                  else
                    log_time "No matching files found for pattern: ${GEN_DATA_PATH}/dsbenchmark/[0-9]*/${table_name}_[0-9]*_[0-9]*.dat"
                  fi
                done
            done
        else
            if [ "${LOG_DEBUG}" == "true" ]; then
              log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -f ${PWD}/${i} -v DB_SCHEMA_NAME=\"${DB_SCHEMA_NAME}\" -v DB_EXT_SCHEMA_NAME=\"${DB_EXT_SCHEMA_NAME}\" | grep INSERT | awk -F ' ' '{print \$3}'"
            fi
            tuples=$(
                psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -f "${PWD}/${i}" \
                    -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v DB_EXT_SCHEMA_NAME="${DB_EXT_SCHEMA_NAME}" | grep INSERT | awk -F ' ' '{print $3}'
                exit ${PIPESTATUS[0]}
            )
        fi

        print_log ${tuples}

        # Release the token
        echo >&5
    } &
done

# Wait for all background tasks to complete
wait

# Close the file descriptor
exec 5>&-

log_time "Finished loading tables. Time elapsed: ${SECONDS} seconds."

log_time "Starting post loading processing..."

if [ "${DB_VERSION}" == "postgresql" ]; then
  log_time "Create indexes and keys on PostgreSQL"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -f ${PWD}/100.postgresql.indexkeys.sql -v DB_SCHEMA_NAME=\"${DB_SCHEMA_NAME}\""
  fi
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -f ${PWD}/100.postgresql.indexkeys.sql -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}"
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -c "SELECT tablename, indexname FROM pg_indexes WHERE schemaname = '${DB_SCHEMA_NAME}' ORDER BY tablename, indexname;"
fi

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Clean up gpfdist"
fi

if [ "${RUN_MODEL}" == "remote" ]; then
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Clean up gpfdist on client"
  fi
  sh ${PWD}/stop_gpfdist.sh
elif [ "${RUN_MODEL}" == "local" ]; then
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Clean up gpfdist on all segments"
  fi
  stop_gpfdist
fi

log_time "Step ${step} finished"
printf "\n"