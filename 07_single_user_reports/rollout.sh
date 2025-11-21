#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

step="single_user_reports"

log_time "Step ${step} started"

init_log ${step}

report_schema="${DB_SCHEMA_NAME}_reports"

SF=${GEN_DATA_SCALE}
filter="gpdb"

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Creating ${report_schema} schema and tables."
fi
# Process SQL files in numeric order, using absolute paths
for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${filter}.*.sql" -printf "%f\n" | sort -n); do
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -f ${PWD}/${i} -v report_schema=${report_schema}"
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -f "${PWD}/${i}" -v report_schema=${report_schema} > /dev/null
  else
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -e -A -f "${PWD}/${i}" -v report_schema=${report_schema} > /dev/null 2>&1
  fi
done

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Start loading log files to ${report_schema} tables."
fi
# Process copy files in numeric order, using absolute paths
for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.copy.*.sql" -printf "%f\n" | sort -n); do
  logstep=$(echo "${i}" | awk -F 'copy.' '{print $2}' | awk -F '.' '{print $1}')
  logfile="${TPC_DS_DIR}/log/rollout_${logstep}.log"
  loadsql="\COPY ${report_schema}.${logstep} FROM '${logfile}' WITH DELIMITER '|';"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -c \"${loadsql}\""
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -c "${loadsql}"
  else
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "${loadsql}"
  fi
done

if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Completed loading log files to ${report_schema} tables."
fi
# psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select 'analyze ' || n.nspname || '.' || c.relname || ';' from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = '${report_schema}'" | psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -t -A -e
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "psql -t -A ${PSQL_OPTIONS} -c \"select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${report_schema}';\" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql -e -A ${PSQL_OPTIONS} -c \"{}\""
  psql -t -A ${PSQL_OPTIONS} -c "select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${report_schema}';" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql -e -A ${PSQL_OPTIONS} -c "{}"
else
  psql -t -A ${PSQL_OPTIONS} -c "select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${report_schema}';" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql -q -A ${PSQL_OPTIONS} -c "{}"
fi
if [ "${LOG_DEBUG}" == "true" ]; then
  log_time "Completed analyzing ${report_schema} tables."
fi

echo "********************************************************************************"
echo "Generate Data"
echo "********************************************************************************"
psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -P pager=off -f ${PWD}/gen_data_report.sql -v report_schema=${report_schema}
echo ""
echo "********************************************************************************"
echo "Data Loads"
echo "********************************************************************************"
psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -P pager=off -f ${PWD}/loads_report.sql -v report_schema=${report_schema}
echo ""
echo "********************************************************************************"
echo "Analyze"
echo "********************************************************************************"
psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -P pager=off -f ${PWD}/analyze_report.sql -v report_schema=${report_schema}
echo ""
echo ""
echo "********************************************************************************"
echo "Queries"
echo "********************************************************************************"
psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -P pager=off -f ${PWD}/queries_report.sql -v report_schema=${report_schema}
echo ""

echo "********************************************************************************"
echo "Summary"
echo "********************************************************************************"
echo ""

GEN_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select round(extract('epoch' from duration)) from ${report_schema}.gen_data")
LOAD_TIME_SERIAL=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select round(sum(extract('epoch' from duration))) from ${report_schema}.load where tuples > 0")
LOAD_TIME_PARALLEL=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "SELECT ROUND(MAX(end_epoch_seconds) - MIN(start_epoch_seconds)) FROM ${report_schema}.load WHERE tuples > 0")
ANALYZE_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select round(sum(extract('epoch' from duration))) from ${report_schema}.analyze where tuples = -1")
QUERIES_TIME=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select round(sum(extract('epoch' from duration))) from (SELECT split_part(description, '.', 2) AS id, min(duration) AS duration FROM ${report_schema}.sql where tuples >= 0 GROUP BY split_part(description, '.', 2)) as sub")
SUCCESS_QUERY=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select count(*) from ${report_schema}.sql where tuples >= 0")
FAILD_QUERY=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "select count(*) from ${report_schema}.sql where tuples < 0 and id > 1")

printf "Scale Factor (SF)\t\t\t%d\n" "${SF}"
printf "Generate Data (seconds)\t\t\t%d\n" "${GEN_TIME}"
printf "Load SERIAL (seconds)\t\t\t%d\n" "${LOAD_TIME_SERIAL}"
printf "Load PARALLEL (seconds)\t\t\t%d\n" "${LOAD_TIME_PARALLEL}"
printf "Analyze (seconds)\t\t\t%d\n" "${ANALYZE_TIME}"
printf "1 User Queries (seconds)\t\t%d\tFor %d success queries and %d failed queries\n" "${QUERIES_TIME}" "${SUCCESS_QUERY}" "${FAILD_QUERY}"
echo ""
echo "********************************************************************************"

log_time "Step ${step} finished"
printf "\n"
