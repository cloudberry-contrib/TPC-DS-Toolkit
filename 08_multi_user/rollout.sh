#!/bin/bash

set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})
step="multi_user"

log_time "Step ${step} started"

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
# define data loding log file
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

if [ "${MULTI_USER_COUNT}" -eq "0" ]; then
  echo "MULTI_USER_COUNT set at 0 so exiting..."
  exit 0
fi

function get_running_jobs_count() {
  job_count=$(ps -fu "${ADMIN_USER}" |grep -v grep |grep "08_multi_user/test.sh"|wc -l || true)
  echo "${job_count}"
}

function get_file_count() {
  file_count=$(find ${TPC_DS_DIR}/log -maxdepth 1 -name 'end_testing*' | grep -c . || true)
  echo "${file_count}"
}

rm -f ${TPC_DS_DIR}/log/end_testing_*.log
rm -f ${TPC_DS_DIR}/log/testing*.log
rm -f ${TPC_DS_DIR}/log/rollout_testing_*.log
rm -f ${TPC_DS_DIR}/log/*multi.explain_analyze.log

function generate_templates() {
  log_time "Start generate SQL Scripts for ${MULTI_USER_COUNT} users"
  SECONDS=0

  rm -f "${PWD}"/query_*.sql
  #create each user's directory
  sql_dir="${PWD}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "sql_dir: ${sql_dir}"
  fi
  for i in $(seq 1 ${MULTI_USER_COUNT}); do
    sql_dir="${PWD}/${i}"
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "checking for directory ${sql_dir}"
    fi
    if [ ! -d "${sql_dir}" ]; then
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "mkdir ${sql_dir}"
      fi
      mkdir "${sql_dir}"
    fi
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "rm -f ${sql_dir}/*.sql"
    fi
    rm -f "${sql_dir}"/*.sql
  done

  # Create queries
  cd "${PWD}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "dsqgen -streams ${MULTI_USER_COUNT} -input ${PWD}/query_templates/templates.lst -directory ${PWD}/query_templates -dialect cloudberry -scale ${GEN_DATA_SCALE} -RNGSEED ${RNGSEED} -verbose y -output ${PWD}"
    "${PWD}/dsqgen" -streams ${MULTI_USER_COUNT} -input "${PWD}/query_templates/templates.lst" -directory "${PWD}/query_templates" -dialect cloudberry -scale ${GEN_DATA_SCALE} -RNGSEED ${RNGSEED} -verbose y -output "${PWD}" 
  else
    "${PWD}/dsqgen" -streams ${MULTI_USER_COUNT} -input "${PWD}/query_templates/templates.lst" -directory "${PWD}/query_templates" -dialect cloudberry -scale ${GEN_DATA_SCALE} -RNGSEED ${RNGSEED} -verbose y -output "${PWD}" > /dev/null 2>&1
  fi

  # Move query files to session directories in numerical order
  for i in $(find "${PWD}" -maxdepth 1 -type f -name "query_*.sql" -printf "%f\n" | sort -n); do
    stream_number=$(echo "${i}" | awk -F '[_.]' '{print $2}')
    # Going from base 0 to base 1
    stream_number=$((stream_number + 1))
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "stream_number: ${stream_number}"
    fi
    sql_dir="${PWD}/${stream_number}"
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "mv ${PWD}/${i} ${sql_dir}/"
    fi
    mv "${PWD}/${i}" "${sql_dir}/"
  done
  log_time "Completed generate SQL Scripts for ${MULTI_USER_COUNT} users in ${SECONDS} seconds"
}

if [ "${RUN_MULTI_USER_QGEN}" = "true" ]; then
  generate_templates
fi

for session_id in $(seq 1 ${MULTI_USER_COUNT}); do
  session_log="${TPC_DS_DIR}/log/testing_session_${session_id}.log"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "${PWD}/test.sh ${session_id}"
  fi
  ${PWD}/test.sh ${session_id} &> ${session_log} &
done

log_time "Now executing ${MULTI_USER_COUNT} multi-user queries. This may take a while."
seconds=0
echo -n "Multi-user query duration: "
running_jobs_count=$(get_running_jobs_count)
while [ ${running_jobs_count} -gt 0 ]; do
  printf "\rMulti-user query duration: ${seconds} second(s)"
  sleep 15
  running_jobs_count=$(get_running_jobs_count)
  seconds=$((seconds + 15))
done
echo ""
log_time "Multi-user queries completed."

file_count=$(get_file_count)

if [ "${file_count}" -ne "${MULTI_USER_COUNT}" ]; then
  log_time "The number of successfully completed sessions, ${file_count}, is less than the ${MULTI_USER_COUNT} expected!"
  log_time "Please review the log files to determine which queries failed."
  exit 1
fi

rm -f ${TPC_DS_DIR}/log/end_testing_*.log # remove the counter log file if successful.

log_time "Step ${step} finished"
printf "\n"
