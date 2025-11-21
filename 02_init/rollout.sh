#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})

step="init"

log_time "Step ${step} started"

init_log ${step}
start_log
schema_name=${DB_VERSION}
export schema_name
table_name="init"
export table_name

function check_gucs() {
  update_config="0"

  if [ "${DB_VERSION}" == "gpdb_4_3" ] || [ "${DB_VERSION}" == "gpdb_5" ]; then
    counter=$(
      psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "show optimizer_join_arity_for_associativity_commutativity" | grep -i "18" | wc -l
      exit ${PIPESTATUS[0]}
    )
    if [ "${counter}" -eq "0" ]; then
      log_time "setting optimizer_join_arity_for_associativity_commutativity"
      gpconfig -c optimizer_join_arity_for_associativity_commutativity -v 18 --skipvalidation
      update_config="1"
    fi
  fi

  log_time "check optimizer"
  counter=$(
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "show optimizer" | grep -i "on" | wc -l
    exit ${PIPESTATUS[0]}
  )
  if [ "${counter}" -eq "0" ]; then
    log_time "enabling optimizer"
    gpconfig -c optimizer -v on --masteronly
    update_config="1"
  fi

  log_time "check analyze_root_partition"
  counter=$(
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "show optimizer_analyze_root_partition" | grep -i "on" | wc -l
    exit ${PIPESTATUS[0]}
  )
  if [ "${counter}" -eq "0" ]; then
    log_time "enabling analyze_root_partition"
    gpconfig -c optimizer_analyze_root_partition -v on --masteronly
    update_config="1"
  fi

  log_time "check gp_autostats_mode"
  counter=$(
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "show gp_autostats_mode" | grep -i "none" | wc -l
    exit ${PIPESTATUS[0]}
  )
  if [ "${counter}" -eq "0" ]; then
    log_time "changing gp_autostats_mode to none"
    gpconfig -c gp_autostats_mode -v none --masteronly
    update_config="1"
  fi

  log_time "check default_statistics_target"
  counter=$(
    psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -t -A -c "show default_statistics_target" | grep "100" | wc -l
    exit ${PIPESTATUS[0]}
  )
  if [ "${counter}" -eq "0" ]; then
    log_time "changing default_statistics_target to 100"
    gpconfig -c default_statistics_target -v 100
    update_config="1"
  fi

  if [ "$update_config" -eq "1" ]; then
    log_time "update cluster because of config changes"
    gpstop -u
  fi
}

function copy_config() {
  log_time "Copying configuration files..."
  if [ -n "${MASTER_DATA_DIRECTORY}" ]; then
    cp "${MASTER_DATA_DIRECTORY}/pg_hba.conf" "${TPC_DS_DIR}/log/pg_hba_${DB_VERSION}.conf"
    cp "${MASTER_DATA_DIRECTORY}/postgresql.conf" "${TPC_DS_DIR}/log/postgresql.conf_${DB_VERSION}.conf"
  elif [ -n "${COORDINATOR_DATA_DIRECTORY}" ]; then
    cp "${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf" "${TPC_DS_DIR}/log/pg_hba_${DB_VERSION}.conf"
    cp "${COORDINATOR_DATA_DIRECTORY}/postgresql.conf" "${TPC_DS_DIR}/log/postgresql.conf_${DB_VERSION}.conf"
  else
    log_time "WARNING: Unable to find the master or coordinator data directory."
    log_time "Please check your environment settings (MASTER_DATA_DIRECTORY or COORDINATOR_DATA_DIRECTORY)."
  fi

  # Save segment configuration to log
  psql ${PSQL_OPTIONS} -v ON_ERROR_STOP=1 -q -A -t -c "SELECT * FROM gp_segment_configuration" -o "${TPC_DS_DIR}/log/gp_segment_configuration_${DB_VERSION}.txt"
}

if [ "${RUN_MODEL}" != "local" ]; then
  log_time "Running in non-local mode"
  # Add any specific commands for REMOTE mode here
else
  log_time "Running in LOCAL mode"
  check_gucs
  copy_config
fi

print_log

log_time "Step ${step} finished"
printf "\n"
