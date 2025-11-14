#!/bin/bash
set -e

PWD=$(get_pwd ${BASH_SOURCE[0]})
step="compile_tpcds"

log_time "Step ${step} started"
printf "\n"

init_log ${step}
start_log
schema_name="${DB_VERSION}"
export schema_name
table_name="compile"
export table_name

compile_flag="true"

function make_tpc() {
  #compile the tools
  unzip -o -d ${TPC_DS_DIR}/00_compile_tpcds/ ${TPC_DS_DIR}/00_compile_tpcds/DSGen-software-code-4.0.0.zip
  cd ${TPC_DS_DIR}/00_compile_tpcds/DSGen-software-code-4.0.0/tools/
  rm -f ./*.o
  make clean
  ADDITIONAL_CFLAGS_OPTION="-g -Wno-unused-function -Wno-unused-but-set-variable -Wno-format -fcommon" LDFLAGS="-Wl,--allow-multiple-definition" make
  cp dsqgen ${TPC_DS_DIR}/00_compile_tpcds/tools/
  cp dsdgen ${TPC_DS_DIR}/00_compile_tpcds/tools/
  cp tpcds.idx ${TPC_DS_DIR}/00_compile_tpcds/tools/
  cd ../../
}


function copy_tpc() {
  cp ${TPC_DS_DIR}/00_compile_tpcds/tools/dsqgen ../*_sql/
  cp ${TPC_DS_DIR}/00_compile_tpcds/tools/dsqgen ../*_multi_user/
  cp ${TPC_DS_DIR}/00_compile_tpcds/tools/dsdgen ../*_gen_data/
  cp ${TPC_DS_DIR}/00_compile_tpcds/tools/tpcds.idx ../*_sql/
  cp ${TPC_DS_DIR}/00_compile_tpcds/tools/tpcds.idx ../*_multi_user/
  cp ${TPC_DS_DIR}/00_compile_tpcds/tools/tpcds.idx ../*_gen_data/

  #copy the compiled dsdgen program to the segment nodes when running in LOCAL mode
  if [ "${RUN_MODEL}" == "local" ]; then
    log_time "copy tpcds binaries to segment hosts"
    log_time "RUN_MODEL is LOCAL, proceeding with copying binaries"
    set +e  # Temporarily disable error exit to capture SSH failures
    local ssh_failed=0
    for i in $(cat ${TPC_DS_DIR}/segment_hosts.txt); do
      scp tools/dsdgen tools/tpcds.idx ${i}: 2>/dev/null
      if [ $? -ne 0 ]; then
        log_time "Error: Failed to copy binaries to host ${i}"
        ssh_failed=1
      fi
    done
    set -e  # Restore error exit
    
    # If any SSH connection failed, exit the program
    if [ $ssh_failed -eq 1 ]; then
      log_time "[ERROR] Failed to connect to some segment hosts. Exiting."
      log_time "Some segment hosts are not reachable, check network connection or try CLOUD mode."
      exit 1
    fi
  else
    log_time "RUN_MODEL is not LOCAL, skipping copying binaries"
  fi
}


function copy_queries() {
  rm -rf ${TPC_DS_DIR}/*_sql/query_templates
  rm -rf ${TPC_DS_DIR}/*_multi_user/query_templates
  cp -R query_templates ${TPC_DS_DIR}/*_sql/
  cp -R query_templates ${TPC_DS_DIR}/*_multi_user/
}

function check_binary() {
  set +e
  
  cd ${TPC_DS_DIR}/00_compile_tpcds/tools/
  cp -f dsqgen.${CHIP_TYPE} dsqgen
  cp -f dsdgen.${CHIP_TYPE} dsdgen
  chmod +x dsqgen
  chmod +x dsdgen

  ./dsqgen -help
  if [ $? == 0 ]; then 
    ./dsdgen -help
    if [ $? == 0 ]; then
      compile_flag="false" 
    fi
  fi
  cd ..
  set -e
}

function check_chip_type() {
  # Get system architecture information
  ARCH=$(uname -m)

  # Determine the architecture type and assign to variable
  if [[ $ARCH == *"x86"* || $ARCH == *"i386"* || $ARCH == *"i686"* ]]; then
    export CHIP_TYPE="x86"
  elif [[ $ARCH == *"arm"* || $ARCH == *"aarch64"* ]]; then
    export CHIP_TYPE="arm"
  else
    export CHIP_TYPE="unknown"
  fi

  # Print the result for verification
  echo "Chip type: $CHIP_TYPE"
}

check_chip_type
check_binary

if [ "${compile_flag}" == "true" ]; then
  make_tpc
else
  echo "Binary works, no compiling needed."
fi
create_hosts_file
copy_tpc
copy_queries
print_log

log_time "Step ${step} finished"
printf "\n"