#!/bin/bash

set -e
PWD=$(get_pwd ${BASH_SOURCE[0]})

################################################################################
####  Local functions  #########################################################
################################################################################
function create_directories() {
  if [ ! -d ${TPC_DS_DIR}/log ]; then
    echo "Creating log directory"
    mkdir ${TPC_DS_DIR}/log
  fi
}

################################################################################
####  Body  ####################################################################
################################################################################
create_directories

echo "############################################################################"
echo "TPC-DS Script for PostgreSQL / Cloudberry Database."
echo "############################################################################"
echo ""
echo "############################################################################"
echo "All parameter settings:"
echo "############################################################################"

grep -E '^[[:space:]]*export[[:space:]]+' tpcds_variables.sh | grep -v '^[[:space:]]*#' | while read -r line; do
  var_name=$(echo "$line" | awk '{print $2}' | cut -d= -f1)
  printf "%s: %s\n" "$var_name" "${!var_name}"
done

echo "############################################################################"
echo ""

# We assume that the flag variable names are consistent with the corresponding directory names
for i in $(find ${PWD} -maxdepth 1 -type d -name "[0-9]*" | sort -n); do
  # Get just the directory name without the path
  dir_name=$(basename "$i")
  # split by the first underscore and extract the step name
  step_name=${dir_name#*_}
  step_name=${step_name%%/}
  # convert to upper case and concatenate "RUN_" in the front to get the flag name
  flag_name="RUN_$(echo ${step_name} | tr "[:lower:]" "[:upper:]")"
  # use indirect reference to convert flag name string to its value
  run_flag=${!flag_name}

  if [ "${run_flag}" == "true" ]; then
    echo "Run ${i}/rollout.sh"
    ${i}/rollout.sh
  elif [ "${run_flag}" == "false" ]; then
    echo "Skip ${i}/rollout.sh"
  else
    echo "Aborting script because ${flag_name} is not properly specified: must be either \"true\" or \"false\"."
    exit 1
  fi
done
