#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

step="analyze"

log_time "Step ${step} started"

init_log ${step}

log_time "Analyze tables"

start_log

schema_name=${DB_SCHEMA_NAME}
table_name="analyzedb"
id=""

if [ "${RUN_ANALYZE}" == "true" ]; then

  log_time "Analyze tables started:"
  SECONDS=0
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "psql ${PSQL_OPTIONS} -t -A -c \"select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${DB_SCHEMA_NAME}' and tablename NOT like '%prt%';\" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql ${PSQL_OPTIONS} -e -q -A -c \"{}\""
    psql ${PSQL_OPTIONS} -t -A -c "select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${DB_SCHEMA_NAME}' and tablename NOT like '%prt%';" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql ${PSQL_OPTIONS} -e -q -t -A -c "{}"
  else
    psql ${PSQL_OPTIONS} -t -A -c "select 'analyze ' ||schemaname||'.'||tablename||';' from pg_tables WHERE schemaname = '${DB_SCHEMA_NAME}' and tablename NOT like '%prt%';" |xargs -I {} -P ${RUN_ANALYZE_PARALLEL} psql ${PSQL_OPTIONS} -q -t -A -c "{}"
  fi

  #make sure root stats are gathered
  if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ] || [ "${DB_VERSION}" == "gpdb_6" ]; then
    SQL_QUERY="select n.nspname, c.relname from pg_class c join pg_namespace n on c.relnamespace = n.oid left outer join (select starelid from pg_statistic group by starelid) s on c.oid = s.starelid join (select tablename from pg_partitions group by tablename) p on p.tablename = c.relname where n.nspname = '${DB_SCHEMA_NAME}' and s.starelid is null order by 1, 2"
  else
    SQL_QUERY="select n.nspname, c.relname from pg_class c join pg_namespace n on c.relnamespace = n.oid left outer join (select starelid from pg_statistic group by starelid) s on c.oid = s.starelid join pg_partitioned_table p on p.partrelid = c.oid where n.nspname = '${DB_SCHEMA_NAME}' and s.starelid is null order by 1, 2"
  fi

  for t in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "${SQL_QUERY}"); do
    schema_name=$(echo ${t} | awk -F '|' '{print $1}')
    table_name=$(echo ${t} | awk -F '|' '{print $2}')
    log_time "Missing root stats for ${schema_name}.${table_name}"
    SQL_QUERY="ANALYZE ROOTPARTITION ${schema_name}.${table_name}"
    log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c \"${SQL_QUERY}\""
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "${SQL_QUERY}"
  done
  log_time "Analyze tables finished. Time elapsed: ${SECONDS} seconds."
else
  echo "Analyze tables Skipped..."
fi

tuples="-1"
print_log ${tuples}

log_time "Step ${step} finished"
printf "\n"