#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})
step="multi_user_reports"

log_time "Step ${step} started"

init_log ${step}

filter="gpdb"

multi_user_report_schema="${DB_SCHEMA_NAME}_multi_user_reports"

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Creating ${multi_user_report_schema} schema and tables."
fi
# Process SQL files in numeric order with absolute paths
for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${filter}.*.sql" -printf "%f\n" | sort -n); do
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -f ${PWD}/${i} -v multi_user_report_schema=${multi_user_report_schema}"
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -f "${PWD}/${i}" -v multi_user_report_schema=${multi_user_report_schema}
  else
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -f "${PWD}/${i}" -v multi_user_report_schema=${multi_user_report_schema} > /dev/null 2>&1
  fi
done
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Start loading log files to ${multi_user_report_schema} tables."
fi
# Process copy files in numeric order with absolute paths
for i in $(find "${TPC_DS_DIR}/log" -maxdepth 1 -type f -name "rollout_testing_*" -printf "%f\n" | sort -n); do
  logfile="${TPC_DS_DIR}/log/${i}"
  loadsql="\COPY ${multi_user_report_schema}.sql FROM '${logfile}' WITH DELIMITER '|';"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -c \"${loadsql}\""
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -c "${loadsql}"
  else
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -c "${loadsql}"
  fi
  
done
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Completed loading log files to ${multi_user_report_schema} tables."
fi

psql -t -A ${PSQL_OPTIONS} -c "select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${multi_user_report_schema}';" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql -q -A ${PSQL_OPTIONS} -c "{}" > /dev/null 2>&1

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Completed analyzing ${multi_user_report_schema} tables."
fi

# Generate detailed report
log_time "Generating detailed report"
psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -P pager=off -f "${PWD}/detailed_report.sql" -v multi_user_report_schema=${multi_user_report_schema}
echo ""

CONCURRENT_QUERY_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select round(sum(extract('epoch' from duration))) from ${multi_user_report_schema}.sql")
THROUGHPUT_ELAPSED_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select max(end_epoch_seconds) - min(start_epoch_seconds) from ${multi_user_report_schema}.sql")

S_Q=${MULTI_USER_COUNT}
SF=${GEN_DATA_SCALE}

SUCCESS_QUERY=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select count(*) from ${multi_user_report_schema}.sql where tuples >= 0")
FAILD_QUERY=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select count(*) from ${multi_user_report_schema}.sql where tuples < 0 and id > 1")


echo "********************************************************************************"
echo "Summary"
echo "********************************************************************************"
echo ""

printf "Number of Streams (Sq)\t%d\n" "${S_Q}"
printf "Scale Factor (SF)\t%d\n" "${SF}"
printf "Sum of Elapse Time for all Concurrent Queries (seconds)\t%d\n" "${CONCURRENT_QUERY_TIME}"
printf "Throughput Test Elapsed Time (seconds)\t%d\tFor %d success queries and %d failed queries\n" "${THROUGHPUT_ELAPSED_TIME}" "${SUCCESS_QUERY}" "${FAILD_QUERY}"
printf "\n"
echo "********************************************************************************"

log_time "Step ${step} finished"
printf "\n"
