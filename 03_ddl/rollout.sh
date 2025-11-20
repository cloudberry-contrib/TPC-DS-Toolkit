#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

step="ddl"

log_time "Step ${step} started"

init_log ${step}

filter="gpdb"

if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then

  distkeyfile="distribution_original.txt"
else
  distkeyfile="distribution.txt"
fi

if [ "${DROP_EXISTING_TABLES}" == "true" ]; then
  log_time "Creating TPC-DS tables."
  SECONDS=0
  # Create tables - process SQL files in numeric order
  for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${filter}.*.sql" -printf "%f\n" | sort -n); do
    start_log
    id=$(echo "${i}" | awk -F '.' '{print $1}')
    export id
    schema_name=${DB_SCHEMA_NAME}
    #schema_name=$(echo ${i} | awk -F '.' '{print $2}')
    export schema_name
    table_name=$(echo ${i} | awk -F '.' '{print $3}')
    export table_name

    if [ "${RANDOM_DISTRIBUTION}" == "true" ]; then
      DISTRIBUTED_BY="DISTRIBUTED RANDOMLY"
    else
      for z in $(cat ${PWD}/${distkeyfile}); do
        table_name2=$(echo ${z} | awk -F '|' '{print $2}')
        if [ "${table_name2}" == "${table_name}" ]; then
          distribution=$(echo ${z} | awk -F '|' '{print $3}')
        fi
      done
      
      if [ "${distribution^^}" == "REPLICATED" ]; then
        DISTRIBUTED_BY="DISTRIBUTED REPLICATED"
      else
        DISTRIBUTED_BY="DISTRIBUTED BY (${distribution})"
      fi
    fi

    if [ "${DB_VERSION}" == "hashdata_enterprise_4" ]; then
      DISTRIBUTED_BY=""
      TABLE_ACCESS_METHOD=""
    fi

    if [ "${DB_VERSION}" == "postgresql" ]; then
      DISTRIBUTED_BY=""
      TABLE_ACCESS_METHOD=""
      TABLE_STORAGE_OPTIONS=""
    fi

    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -q -A -t -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME=\"${DB_SCHEMA_NAME}\" -v DB_EXT_SCHEMA_NAME=\"${DB_EXT_SCHEMA_NAME}\" -v ACCESS_METHOD=\"${TABLE_ACCESS_METHOD}\" -v STORAGE_OPTIONS=\"${TABLE_STORAGE_OPTIONS}\" -v DISTRIBUTED_BY=\"${DISTRIBUTED_BY}\""
      psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -P pager=off -f "${PWD}/${i}" -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v DB_EXT_SCHEMA_NAME="${DB_EXT_SCHEMA_NAME}" -v ACCESS_METHOD="${TABLE_ACCESS_METHOD}" -v STORAGE_OPTIONS="${TABLE_STORAGE_OPTIONS}" -v DISTRIBUTED_BY="${DISTRIBUTED_BY}"
      echo ""
    else
      psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -P pager=off -f "${PWD}/${i}" -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v DB_EXT_SCHEMA_NAME="${DB_EXT_SCHEMA_NAME}" -v ACCESS_METHOD="${TABLE_ACCESS_METHOD}" -v STORAGE_OPTIONS="${TABLE_STORAGE_OPTIONS}" -v DISTRIBUTED_BY="${DISTRIBUTED_BY}" > /dev/null 2>&1
    fi
    print_log
  done

  # Process partition files in numeric order
  if [ "${TABLE_USE_PARTITION}" == "true" ]; then
    for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.${filter}.*.partition" -printf "%f\n" | sort -n); do
      start_log
      id=$(echo "${i}" | awk -F '.' '{print $1}')
      export id
      schema_name=${DB_SCHEMA_NAME}
      #schema_name=$(echo ${i} | awk -F '.' '{print $2}')
      export schema_name
      table_name=$(echo ${i} | awk -F '.' '{print $3}')
      export table_name

    if [ "${RANDOM_DISTRIBUTION}" == "true" ]; then
      DISTRIBUTED_BY="DISTRIBUTED RANDOMLY"
    else
      for z in $(cat ${PWD}/${distkeyfile}); do
        table_name2=$(echo ${z} | awk -F '|' '{print $2}')
        if [ "${table_name2}" == "${table_name}" ]; then
          distribution=$(echo ${z} | awk -F '|' '{print $3}')
        fi
      done
      
      if [ "${distribution^^}" == "REPLICATED" ]; then
        DISTRIBUTED_BY="DISTRIBUTED REPLICATED"
      else
        DISTRIBUTED_BY="DISTRIBUTED BY (${distribution})"
      fi
    fi

      #Drop existing partition tables if they exist
      SQL_QUERY="drop table if exists ${DB_SCHEMA_NAME}.${table_name} cascade"
      
      if [ "${LOG_DEBUG}" == "true" ]; then
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -t -c "${SQL_QUERY}"
        log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -a -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME=\"${DB_SCHEMA_NAME}\" -v ACCESS_METHOD=\"${TABLE_ACCESS_METHOD}\" -v STORAGE_OPTIONS=\"${TABLE_STORAGE_OPTIONS}\" -v DISTRIBUTED_BY=\"${DISTRIBUTED_BY}\""
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -A -t -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v ACCESS_METHOD="${TABLE_ACCESS_METHOD}" -v STORAGE_OPTIONS="${TABLE_STORAGE_OPTIONS}" -v DISTRIBUTED_BY="${DISTRIBUTED_BY}"
        echo ""
      else
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v ACCESS_METHOD="${TABLE_ACCESS_METHOD}" -v STORAGE_OPTIONS="${TABLE_STORAGE_OPTIONS}" -v DISTRIBUTED_BY="${DISTRIBUTED_BY}" > /dev/null 2>&1
      fi
      print_log
    done
    log_time "TPC-DS tables created in ${SECONDS} seconds."
  fi

  if [ "${RUN_MODEL}" != "cloud" ]; then
    log_time "Creating TPC-DS external tables for loading data in non-cloud model."
    SECONDS=0
    # Process external tables in numeric order
    for i in $(find "${PWD}" -maxdepth 1 -type f -name "*.ext_tpcds.*.sql" -printf "%f\n" | sort -n); do
      start_log
      id=$(echo ${i} | awk -F '.' '{print $1}')
      schema_name=$(echo ${i} | awk -F '.' '{print $2}')
      export schema_name
      table_name=$(echo ${i} | awk -F '.' '{print $3}')
      export table_name
      counter=0
      flag=10
     
      if [ "${RUN_MODEL}" == "remote" ]; then
        EXT_HOST=$(hostname -I | awk '{print $1}')
        # Split CUSTOM_GEN_PATH into array of paths to support multiple directories
        IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"

        for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
          PORT=$((GPFDIST_PORT + flag))
          if [ "${counter}" -eq "0" ]; then
            LOCATION="'"
          else
            LOCATION+="', '"
          fi
          LOCATION+="gpfdist://${EXT_HOST}:${PORT}/[0-9]*/${table_name}_[0-9]*_[0-9]*.dat"
          counter=$((counter + 1))
          let flag=$flag+1
        done
        LOCATION+="'"
      elif [ "${RUN_MODEL}" == "local" ] && [ "${USING_CUSTOM_GEN_PATH_IN_LOCAL_MODE}" == "true" ]; then
        # Handle local mode with custom CUSTOM_GEN_PATH, but still use segment nodes for data
        # Handle custom CUSTOM_GEN_PATH in local mode
        IFS=' ' read -ra GEN_PATHS <<< "${CUSTOM_GEN_PATH}"
        
        if [ ${#GEN_PATHS[@]} -eq 0 ]; then
          log_time "ERROR: CUSTOM_GEN_PATH is empty or not set"
          exit 1
        fi

        for EXT_HOST in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
          # For each path, start a gpfdist instance
          for GEN_DATA_PATH in "${GEN_PATHS[@]}"; do
            PORT=$((GPFDIST_PORT + flag))
            let flag=$flag+1
            
            if [ "${counter}" -eq "0" ]; then
              LOCATION="'"
            else
              LOCATION+="', '"
            fi
              LOCATION+="gpfdist://${EXT_HOST}:${PORT}/[0-9]*/${table_name}_[0-9]*_[0-9]*.dat"
              counter=$((counter + 1))
          done
        done
        LOCATION+="'"
      else
        if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then
          SQL_QUERY="select rank() over (partition by g.hostname order by p.fselocation), g.hostname from gp_segment_configuration g join pg_filespace_entry p on g.dbid = p.fsedbid join pg_tablespace t on t.spcfsoid where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' and t.spcname = 'pg_default' order by g.hostname"
        else
          SQL_QUERY="select rank() over(partition by g.hostname order by g.datadir), g.hostname from gp_segment_configuration g where g.content >= 0 and g.role = '${GPFDIST_LOCATION}' order by g.hostname"
        fi
        
        for x in $(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "${SQL_QUERY}"); do
          CHILD=$(echo ${x} | awk -F '|' '{print $1}')
          EXT_HOST=$(echo ${x} | awk -F '|' '{print $2}')
          PORT=$((GPFDIST_PORT + flag))
          let flag=$flag+1
          if [ "${counter}" -eq "0" ]; then
            LOCATION="'"
          else
            LOCATION+="', '"
          fi
            LOCATION+="gpfdist://${EXT_HOST}:${PORT}/[0-9]*/${table_name}_[0-9]*_[0-9]*.dat"
            counter=$((counter + 1))
        done
        LOCATION+="'"
      fi
      if [ "${LOG_DEBUG}" == "true" ]; then
        log_time "psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -q -t -A -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME=\"${DB_SCHEMA_NAME}\" -v LOCATION=\"${LOCATION}\" -v DB_EXT_SCHEMA_NAME=\"${DB_EXT_SCHEMA_NAME}\""
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -q -t -A -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v LOCATION="${LOCATION}" -v DB_EXT_SCHEMA_NAME="${DB_EXT_SCHEMA_NAME}"
        echo ""
      else
        psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -e -q -t -A -P pager=off -f ${PWD}/${i} -v DB_SCHEMA_NAME="${DB_SCHEMA_NAME}" -v LOCATION="${LOCATION}" -v DB_EXT_SCHEMA_NAME="${DB_EXT_SCHEMA_NAME}" > /dev/null 2>&1
      fi
      print_log
    done
    log_time "TPC-DS external tables created in ${SECONDS} seconds."
  fi
fi

# Check if current user matches BENCH_ROLE
if [ "${DB_CURRENT_USER}" != "${BENCH_ROLE}" ]; then
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Current user ${DB_CURRENT_USER} does not match BENCH_ROLE ${BENCH_ROLE}."
  fi
  DropRoleDenp="drop owned by ${BENCH_ROLE} cascade"
  DropRole="DROP ROLE IF EXISTS ${BENCH_ROLE}"
  CreateRole="CREATE ROLE ${BENCH_ROLE}"
  GrantRole="GRANT ${BENCH_ROLE} TO ${DB_CURRENT_USER}"
  GrantSchemaPrivileges="GRANT ALL PRIVILEGES ON SCHEMA ${DB_SCHEMA_NAME} TO ${BENCH_ROLE}"
  GrantTablePrivileges="GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ${DB_SCHEMA_NAME} TO ${BENCH_ROLE}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "rm -f ${PWD}/GrantTablePrivileges.sql"
  fi
  rm -f ${PWD}/GrantTablePrivileges.sql
  psql ${PSQL_OPTIONS} -tc "SELECT format('GRANT ALL PRIVILEGES ON TABLE %I.%I TO %I;', '${DB_SCHEMA_NAME}', tablename, '${BENCH_ROLE}') FROM pg_tables WHERE schemaname='${DB_SCHEMA_NAME}'" > ${PWD}/GrantTablePrivileges.sql
  # Check if role exists in PostgreSQL

  EXISTS=$(psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "SELECT 1 FROM pg_roles WHERE rolname='${BENCH_ROLE}'")

  # Create role if not exists
  if [ "$EXISTS" != "1" ]; then
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Role ${BENCH_ROLE} does not exist. Creating..."
      log_time "Creating role ${BENCH_ROLE}"
    fi
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${CreateRole}"
  else
    set +e
    if [ "${LOG_DEBUG}" == "true" ]; then
      log_time "Drop role dependencies for ${BENCH_ROLE}"
    fi
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${DropRoleDenp}"
    set -e
  fi
  
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Grant role ${BENCH_ROLE} to user ${DB_CURRENT_USER}"
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -e -P pager=off -c "${GrantRole}"
  else
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${GrantRole}" > /dev/null 2>&1
  fi
  
  
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Grant schema privileges to role ${BENCH_ROLE}"
  fi
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${GrantSchemaPrivileges}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Grant table privileges to role ${BENCH_ROLE}"
  fi
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -c "${GrantTablePrivileges}"
  if [ "${LOG_DEBUG}" == "true" ]; then
    log_time "Grant table privileges to role ${BENCH_ROLE}"
  fi
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=0 -q -P pager=off -f ${PWD}/GrantTablePrivileges.sql

fi

log_time "Step ${step} finished"
printf "\n"
