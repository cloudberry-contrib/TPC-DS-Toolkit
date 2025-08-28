#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})
step="multi_user_reports"

log_time "Step ${step} started"
printf "\n"


init_log ${step}

filter="gpdb"

# Process SQL files in numeric order with absolute paths
for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${filter}.*.sql" -printf "%f\n" | sort -n); do
  log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -a -f ${PWD}/${i}"
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -a -f "${PWD}/${i}"
  echo ""
done

# Process copy files in numeric order with absolute paths
for i in $(find "${TPC_DS_DIR}/log" -maxdepth 1 -type f -name "rollout_testing_*" -printf "%f\n" | sort -n); do
  logfile="${TPC_DS_DIR}/log/${i}"
  loadsql="\COPY tpcds_testing.sql FROM '${logfile}' WITH DELIMITER '|';"
  log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -a -c \"${loadsql}\""
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -a -c "${loadsql}"
  echo ""
done

psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -t -A -c "select 'analyze ' || n.nspname || '.' || c.relname || ';' from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'tpcds_testing'" | psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -t -A -e

# Generate detailed report
log_time "Generating detailed report"
psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -P pager=off -f "${PWD}/detailed_report.sql"
echo ""

CONCURRENT_QUERY_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select round(sum(extract('epoch' from duration))) from tpcds_testing.sql")
THROUGHPUT_ELAPSED_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select max(end_epoch_seconds) - min(start_epoch_seconds) from tpcds_testing.sql")

S_Q=${MULTI_USER_COUNT}
SF=${GEN_DATA_SCALE}

echo "********************************************************************************"
echo "Summary"
echo "********************************************************************************"
echo ""

printf "Number of Streams (Sq)\t%d\n" "${S_Q}"
printf "Scale Factor (SF)\t%d\n" "${SF}"
printf "Sum of Elapse Time for all Concurrent Queries (seconds)\t%d\n" "${CONCURRENT_QUERY_TIME}"
printf "Throughput Test Elapsed Time (seconds)\t%d\n" "${THROUGHPUT_ELAPSED_TIME}"
printf "\n"
echo "********************************************************************************"

echo "Finished ${step}"
log_time "Step ${step} finished"
printf "\n"
