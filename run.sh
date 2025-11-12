#/bin/bash
function log_time() {
  printf "[%s] %b\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$1"
}
export -f log_time

logfilename=$(date +%Y%m%d)_$(date +%H%M%S)

nohup sh tpcds.sh > tpcds_$logfilename.log 2>&1 &

log_time "Benchmark started running in the background, please check tpcds_$logfilename.log for more information."
log_time "To stop the benchmark, run: kill \$(ps -ef | grep tpcds.sh | grep -v grep | awk '{print \$2}')"
log_time "To check the status of the benchmark, run: tail -f tpcds_$logfilename.log"
