#/bin/bash

function log_time() {
  printf "[%s] %b\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$1"
}
export -f log_time

logfilename=$(date +%Y%m%d)_$(date +%H%M%S)

# Backup the log folder before running the benchmark
LOG_FOLDER=${TPC_DS_DIR}/log
LOG_FOLDER_BACKUP=${LOG_FOLDER}_backup_$logfilename
cp -r ${LOG_FOLDER} ${LOG_FOLDER_BACKUP}
log_time "Log folder backed up to ${LOG_FOLDER_BACKUP}"

nohup sh tpcds.sh > tpcds_$logfilename.log 2>&1 &

log_time "Benchmark started running in the background, please check tpcds_$logfilename.log for more information."
log_time "To stop the benchmark, run: kill \$(ps -ef | grep tpcds.sh | grep -v grep | awk '{print \$2}')"
log_time "To check the status of the benchmark, run: tail -f tpcds_$logfilename.log"
