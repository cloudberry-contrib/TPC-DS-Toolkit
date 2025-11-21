#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

step="sql"

log_time "Step ${step} started"

init_log ${step}

if [ "${DB_CURRENT_USER}" != "${BENCH_ROLE}" ]; then
  GrantSchemaPrivileges="GRANT ALL PRIVILEGES ON SCHEMA ${DB_SCHEMA_NAME} TO ${BENCH_ROLE}"
  GrantTablePrivileges="GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ${DB_SCHEMA_NAME} TO ${BENCH_ROLE}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Grant schema privileges to role ${BENCH_ROLE}"
  fi
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${GrantSchemaPrivileges}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Grant table privileges to role ${BENCH_ROLE}"
  fi
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${GrantTablePrivileges}"
fi

if [ "${RUN_QGEN}" == true ]; then
  log_time "Generate queries based on scale ${GEN_DATA_SCALE}"
  cd "${PWD}"
  "${PWD}/generate_queries.sh"
fi

rm -f ${TPC_DS_DIR}/log/*single.explain_analyze.log

if [ "${ON_ERROR_STOP}" == 0 ]; then
  set +e
fi

log_time "Running the Power Test...Please wait..."
SECONDS=0
# Loop through SQL files in numeric order
for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${BENCH_ROLE}.*.sql" -printf "%f\n" | sort -n); do
  for _ in $(seq 1 ${SINGLE_USER_ITERATIONS}); do
    id=$(echo "${i}" | awk -F '.' '{print $1}')
    export id
    schema_name=$(echo "${i}" | awk -F '.' '{print $2}')
    export schema_name
    table_name=$(echo "${i}" | awk -F '.' '{print $3}')
    export table_name
    
    start_log
    if [ "${EXPLAIN_ANALYZE}" == "false" ]; then
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE=\"\" -f ${PWD}/${i} | wc -l"
      fi
      tuples=$(
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="" -f "${PWD}/${i}" | wc -l
        exit ${PIPESTATUS[0]}
      )
      if [ $? != 0 ]; then
        tuples="-1"
      fi
    else
      myfilename=$(basename "${i}")
      mylogfile=${TPC_DS_DIR}/log/${myfilename}.single.explain_analyze.log
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE=\"EXPLAIN ANALYZE\" -f ${PWD}/${i} > ${mylogfile}"
      fi
      psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="EXPLAIN ANALYZE" -f "${PWD}/${i}" > "${mylogfile}"
      if [ $? != 0 ]; then
        tuples="-1"
      else
        tuples="0"
      fi
    fi
    print_log ${tuples}
    
    if [[ "${QUERY_INTERVAL}" -ne 0 ]]; then
      sleep "${QUERY_INTERVAL}"
    fi
  done
done
log_time "Power Test finished in ${SECONDS} seconds."

log_time "Step ${step} finished"
printf "\n"