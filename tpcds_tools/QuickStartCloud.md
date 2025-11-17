# TPC-DS Benchmark Toolkit Quick Start Guide for Cloud 

This guide provides step-by-step instructions on how to set up and run the TPC-DS benchmark toolkit on postgresql compatible database. Including Hashdata Enterprise, SynxDB Elastic.

## Prerequisites
When you only have access to a psql client to connect to a postgresql compatible database, the test can be executed in "Cloud" mode, where data generation and loading occur on the client host.

### Running Tests on Remote Client Host
1. A psql client installed with passwordless access to the remote database (.pgpass configured properly if necessary)
2. "PSQL_OPTIONS" must be properly configured in the tpcds_variables.sh file.


## Download and Installation

### Download
Download the toolkit package:
https://github.com/cloudberry-contrib/TPC-DS-Toolkit/archive/refs/tags/v1.3.zip

### Installation
Place the folder in the home directory of the user who will run the tests and update ownership:

```bash
unzip TPC-DS-Toolkit-1.3.zip
mv TPC-DS-Toolkit-1.3 /home/<user>/
chown -R <user>.<user> TPC-DS-Toolkit-1.3
```

### Configure the toolkit parameter file

Before running the tests, we need to review the parameter file and adjust the parameters as needed.

For example: to run a 1TB Power test(Single user test), in a Cloudberry based cluster, following parameters need to be modified: 
```bash
cd ~/TPC-DS-Toolkit-1.3
vim tpcds_variables.sh

## Line 7: Change RUN_MODEL to "cloud"
export RUN_MODEL="cloud"

## Line 12: Set the psql options for the client host, and make sure .pgpass is properly set to avoid password prompt.
export PSQL_OPTIONS="-h mdw -p 5432 -U gpadmin -d cbdb"

## Line 13: Set the path on the client host where the data is generated. Make sure the path exists and has enough space.
export CUSTOM_GEN_PATH="/tmp/dsbenchmark"

## Line 14: Set the parallelism for data generation on the client host.
export GEN_DATA_PARALLEL="2"

## Line 25: GEN_DATA_SCALE set to 1000, indicating generation of 1000GB test data
export GEN_DATA_SCALE="1000"

## Line 87: Set this for HashData Enterprise / SynxDB Elastic. NO effect for Postgresql
export RANDOM_DISTRIBUTION="true"

## Line 90: Set this for HashData Enterprise / SynxDB Elastic. NO effect for Postgresql. Consult your database admin to understand good value for this. 
export STATEMENT_MEM="1.9GB"

## Line 104: Set this for HashData Enterprise / SynxDB Elastic. NO effect for Postgresql
export TABLE_ACCESS_METHOD="USING PAX"

## Line 111: Set this for HashData Enterprise / SynxDB Elastic. NO effect for Postgresql
export TABLE_STORAGE_OPTIONS="compresstype=zstd, compresslevel=5"
```

> Please be aware that, default value for these parameters might be changed in different toolkit versions, this guide is based on TPC-DS Toolkit v1.1.

Parameters need to be adjusted to run multi-user tests (Throughput test).
For example: to run a 5 streams throughput test.

```bash
cd ~/TPC-DS-Toolkit-1.3
vim tpcds_variables.sh

## Line 26: Number of concurrent users during throughput tests
export MULTI_USER_COUNT="5"

## Line 75: Runs the throughput test of the benchmark. This generates multiple query streams using `dsqgen`, which samples the database to find proper filters. For very large databases with many streams, this process can take hours just to generate the queries.
export RUN_MULTI_USER="true"

## Line 79: Generate multi-user test results to the database and print out logs.
export RUN_MULTI_USER_REPORTS="true"

## Line 91: Set this for HashData Enterprise / SynxDB Elastic. NO effect for Postgresql. Consult your database admin to understand good value for this. 
export STATEMENT_MEM_MULTI_USER="1GB"
```

For repeating test runs, the following parameters can be adjusted to skip certain steps to save time.

For example: to skip data generation and data loading steps, set following parameters to false:

```bash
cd ~/TPC-DS-Toolkit-1.3
vim tpcds_variables.sh

## Line 39: Generates flat files for the benchmark in parallel on all segment nodes. Files are stored under the `${PGDATA}/dsbenchmark` directory
export RUN_GEN_DATA="false"
export GEN_NEW_DATA="false"

## Line 43: Sets up GUCs for the database and records segment configurations. Only required if the cluster is reconfigured
export RUN_INIT="false"

## Line 50: Recreates all schemas and tables (including external tables for loading). Set to `false` to keep existing data.
export RUN_DDL="false"
export DROP_EXISTING_TABLES="false"

## Line 54: Loads data from flat files into tables and computes statistics
export RUN_LOAD="false"
```
For more information, please refer to the [README.md](../README.md).

### Execute the test

To run the benchmark, executed following command on client host:

```bash
cd ~/TPC-DS-Toolkit-1.3
./run.sh
```