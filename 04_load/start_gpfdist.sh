#!/bin/bash
set -e

PWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GPFDIST_PORT=${1}
GEN_DATA_PATH=${2}
env_file=${3}
seghost=`hostname`

#if [ -z "$GPHOME" ]; then
#echo "source ${env_file}"
source ${env_file}
#fi

gpfdist -p ${GPFDIST_PORT} -d ${GEN_DATA_PATH} > ${GEN_DATA_PATH}/logs/gpfdist.${GPFDIST_PORT}.log 2>&1 &
pid=$!

if [ "${pid}" -ne "0" ]; then
  sleep .4
  count=$(ps -ef 2> /dev/null | grep -v grep | awk -F ' ' '{print $2}' | grep ${pid} | wc -l)
  if [ "${count}" != "1" ]; then
    echo "Unable to start gpfdist on port ${GPFDIST_PORT}"
    echo "Plese check logfile gpfdist.${GPFDIST_PORT}.log on segment host ${seghost}"
    exit 1
  fi
else
  echo "Unable to start background process for gpfdist on port ${GPFDIST_PORT}"
  echo "Plese check logfile gpfdist.${GPFDIST_PORT}.log on segment host ${seghost}"
  exit 1
fi
