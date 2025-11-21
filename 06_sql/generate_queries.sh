#!/bin/bash

PWD=$(get_pwd ${BASH_SOURCE[0]})
set -e

query_id=1
file_id=101

# Check required parameters
if [ "${GEN_DATA_SCALE}" == "" ] || [ "${BENCH_ROLE}" == "" ]; then
  echo "Usage: generate_queries.sh scale rolename"
  echo "Example: ./generate_queries.sh 100 dsbench"
  echo "This creates queries for 100GB of data."
  exit 1
fi

# Define data loading log file
LOG_FILE="${TPC_DS_DIR}/log/rollout_load.log"

# Handle RNGSEED configuration
if [ "${UNIFY_QGEN_SEED}" == "true" ]; then
  # Use a fixed RNGSEED when unified seed is enabled
  RNGSEED=2016032410
else 
  # Get RNGSEED from log file or use default
  if [[ -f "$LOG_FILE" ]]; then
    RNGSEED=$(tail -n 1 "$LOG_FILE" | cut -d '|' -f 6)
  else
    RNGSEED=2016032410
  fi
fi

# Clean up previous query file
rm -f ${PWD}/query_0.sql

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "${PWD}/dsqgen -input ${PWD}/query_templates/templates.lst -directory ${PWD}/query_templates -dialect cloudberry -scale ${GEN_DATA_SCALE} -RNGSEED ${RNGSEED} -verbose y -output ${PWD}"
  ${PWD}/dsqgen -input ${PWD}/query_templates/templates.lst -directory ${PWD}/query_templates -dialect cloudberry -scale ${GEN_DATA_SCALE} -RNGSEED ${RNGSEED} -verbose y -output ${PWD}
else
  ${PWD}/dsqgen -input ${PWD}/query_templates/templates.lst -directory ${PWD}/query_templates -dialect cloudberry -scale ${GEN_DATA_SCALE} -RNGSEED ${RNGSEED} -verbose y -output ${PWD} > /dev/null 2>&1
fi
# Clean up previous SQL files
rm -f ${TPC_DS_DIR}/06_sql/*.${BENCH_ROLE}.*.sql*

# Process each query template
for p in $(seq 1 99); do
  q=$(printf %02d ${query_id})
  filename=${file_id}.${BENCH_ROLE}.${q}.sql
  template_filename=query${p}.tpl
  start_position=""
  end_position=""
  
  # Find query boundaries
  for pos in $(grep -n ${template_filename} ${PWD}/query_0.sql | awk -F ':' '{print $1}'); do
    if [ "${start_position}" == "" ]; then
      start_position=${pos}
    else
      end_position=${pos}
    fi
  done

  # Create and populate query file
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Creating: ${TPC_DS_DIR}/06_sql/${filename}"
  fi
  printf "set role ${BENCH_ROLE};\nset search_path=${DB_SCHEMA_NAME},public;\n" > ${TPC_DS_DIR}/06_sql/${filename}

  # Set optimizer settings
  for o in $(cat ${TPC_DS_DIR}/01_gen_data/optimizer.txt); do
    q2=$(echo ${o} | awk -F '|' '{print $1}')
    if [ "${p}" == "${q2}" ]; then
      optimizer=$(echo ${o} | awk -F '|' '{print $2}')
    fi
  done
  printf "set optimizer=${optimizer};\n" >> ${TPC_DS_DIR}/06_sql/${filename}
  printf "set statement_mem=\"${STATEMENT_MEM}\";\n" >> ${TPC_DS_DIR}/06_sql/${filename}

  # Add vectorization setting if enabled
  if [ "${ENABLE_VECTORIZATION}" = "on" ]; then
    printf "set vector.enable_vectorization=${ENABLE_VECTORIZATION};\n" >> ${TPC_DS_DIR}/06_sql/${filename}
  fi

  # Add EXPLAIN ANALYZE and query content
  printf ":EXPLAIN_ANALYZE\n" >> ${TPC_DS_DIR}/06_sql/${filename}
  sed -n ${start_position},${end_position}p ${PWD}/query_0.sql >> ${TPC_DS_DIR}/06_sql/${filename}

  # Check database if postgresql then comment out optimizer settings
  if [ "${DB_VERSION}" == "postgresql" ]; then
    sed -i 's/^set optimizer=.*/-- &/' "${TPC_DS_DIR}/06_sql/${filename}"
    sed -i 's/^set statement_mem=.*/-- &/' "${TPC_DS_DIR}/06_sql/${filename}"
  fi
  
  query_id=$((query_id + 1))
  file_id=$((file_id + 1))
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Completed: ${TPC_DS_DIR}/06_sql/${filename}"
  fi
done

# Handle special queries that contain multiple statements
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Processing multi-statement queries..."
fi
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "The following queries contain multiple statements and require additional EXPLAIN_ANALYZE:"
  log_time "Queries: 114, 123, 124, and 139"
fi

arr=("114.${BENCH_ROLE}.14.sql" "123.${BENCH_ROLE}.23.sql" "124.${BENCH_ROLE}.24.sql" "139.${BENCH_ROLE}.39.sql")

for z in "${arr[@]}"; do
  myfilename=${TPC_DS_DIR}/06_sql/${z}
  
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Modifying: ${myfilename}"
  fi
  
  # Find position for inserting EXPLAIN_ANALYZE
  if [ "${ENABLE_VECTORIZATION}" = "on" ]; then
    pos=$(grep -n ";" ${myfilename} | awk -F ':' ' { if (NR > 5) print $1 }' | head -1)
  else
    pos=$(grep -n ";" ${myfilename} | awk -F ':' ' { if (NR > 4) print $1 }' | head -1)  
  fi

  # Insert EXPLAIN_ANALYZE after first query
  pos=$((pos + 1))
  sed -i ''${pos}'i\'$'\n'':EXPLAIN_ANALYZE'$'\n' ${myfilename}
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Modified: ${myfilename}"
  fi
done

log_time "COMPLETE: Generated queries for scale ${GEN_DATA_SCALE} with RNGSEED ${RNGSEED}"