# Environment options

## ADMIN_USER should be set to the OS user that executes this toolkit
export ADMIN_USER="gpadmin"
## BENCH_ROLE should be set to the database user that will be used to run the benchmark
export BENCH_ROLE="dsbench"
## DB_SCHEMA_NAME should be set to the database schema that will be used to store the TPC-DS tables
export DB_SCHEMA_NAME="tpcds"
 
## Set to "local" to run the benchmark on the COORDINATOR host or "cloud" to run the benchmark from a remote client.
export RUN_MODEL="local"

## Default port is configured via the env setting of $PGPORT for user $ADMIN_USER
## Configure the host/port/user to connect to the cluster running the test. Can be left empty when all variables are set for the $ADMIN_USER
## Database user defined in this variable with '-U' will be the user to connect to the database, better to be the same with $BENCH_ROLE
## Database user to run this benchmark, should have enough permissions, better to use supper user.
## eg. export PSQL_OPTIONS="-h 2f445c57-c838-4038-a410-50ee36f9461d.ai -p 5432 -U dsbench"
export PSQL_OPTIONS=""

# Benchmark options
export GEN_DATA_SCALE="1"
export MULTI_USER_COUNT="2"

# Step options

## step 00_compile_tpcds
export RUN_COMPILE_TPCDS="true"

## step 01_gen_data
# To run another TPC-DS with a different BENCH_ROLE using existing tables and data,
# the queries need to be regenerated with the new role.
# Change BENCH_ROLE and set RUN_GEN_DATA to true and GEN_NEW_DATA to false.
# GEN_NEW_DATA only takes effect when RUN_GEN_DATA is true, and the default setting
# should be true under normal circumstances.
export RUN_GEN_DATA="true"
export GEN_NEW_DATA="true"
### Default path to store the generated benchmark data, separated by space for multiple paths.
export CUSTOM_GEN_PATH="/tmp/dsbenchmark"
### How many parallel processes to run on each data path to generate data in all modes
### Default is 2, max is Number of CPU cores / number of data paths used in each modes.  
export GEN_DATA_PARALLEL="2"

### The following variables only take effect when RUN_MODEL is set to "local".
### Use custom setting as CUSTOM_GEN_PATH in local mode on segments
export USING_CUSTOM_GEN_PATH_IN_LOCAL_MODE="false"


## step 02_init
export RUN_INIT="true"

## step 03_ddl
# To run another TPC-DS with a different BENCH_ROLE using existing tables and data,
# change BENCH_ROLE and set RUN_DDL to true and DROP_EXISTING_TABLES to false.
# DROP_EXISTING_TABLES only takes effect when RUN_DDL is true, and the default setting
# should be true under normal circumstances.
export RUN_DDL="true"
export DROP_EXISTING_TABLES="true"

## step 04_load
export RUN_LOAD="true"
### How many parallel processes to load data, default is 2, max is 24.
export LOAD_PARALLEL="2"
### Truncate existing tables before loading data
export TRUNCATE_TABLES="true"

## step 05_analyze
export RUN_ANALYZE="true"
### How many parallel processes to analyze tables, default is 5, max is 24.
export RUN_ANALYZE_PARALLEL="5"

## step 06_sql
export RUN_SQL="true"
## Set to true to generate queries for the TPC-DS benchmark.
export RUN_QGEN="true"
## Set to true to generate queries for the TPC-DS benchmark with a specific seed "2016032410" to grantee the same query generated for all tests.
## Set to false to generate queries with a seed when data loading finishes.
export UNIFY_QGEN_SEED="true"
## Set wait time between each query execution, Set to 1 if you want to stop when an error occurs
export QUERY_INTERVAL="0"
#Set to 1 if you want to stop when error occurs
export ON_ERROR_STOP="0"

## step 07_single_user_reports
export RUN_SINGLE_USER_REPORTS="true"

## step 08_multi_user
export RUN_MULTI_USER="false"
export RUN_MULTI_USER_QGEN="true"

## step 09_multi_user_reports
export RUN_MULTI_USER_REPORTS="false"

## step 10_score
export RUN_SCORE="false"

# Misc options
export LOG_DEBUG="false"
export SINGLE_USER_ITERATIONS="1"
export EXPLAIN_ANALYZE="false"
export RANDOM_DISTRIBUTION="false"
## Set to on/off to enable vectorization
export ENABLE_VECTORIZATION="off"
export STATEMENT_MEM="1GB"
export STATEMENT_MEM_MULTI_USER="1GB"
## Set gpfdist location where gpfdist will run: p (primary) or m (mirror)
export GPFDIST_LOCATION="p"
export OSVERSION=$(uname)
export ADMIN_USER=$(whoami)
export ADMIN_HOME=$(eval echo ${HOME}/${ADMIN_USER})
export MASTER_HOST=$(hostname -s)
export DB_SCHEMA_NAME="$(echo "${DB_SCHEMA_NAME}" | tr '[:upper:]' '[:lower:]')"
export DB_EXT_SCHEMA_NAME="ext_${DB_SCHEMA_NAME}"
export BENCH_ROLE="$(echo "${BENCH_ROLE}" | tr '[:upper:]' '[:lower:]')"
export DB_CURRENT_USER=$(psql ${PSQL_OPTIONS} -t -c "SELECT current_user;" 2>/dev/null | tr -d '[:space:]')

# Storage options
## Support TABLE_ACCESS_METHOD as ao_row / ao_column / heap in both GPDB 7 / CBDB
## Support TABLE_ACCESS_METHOD as "PAX" for PAX table format and remove blocksize option in TABLE_STORAGE_OPTIONS for CBDB 2.0 only.
## TABLE_ACCESS_METHOD only works for Cloudberry and Greenplum 7.0 or later.
# export TABLE_ACCESS_METHOD="USING ao_column"
## Set different storage options for each access method
## Set to use partition for the following tables:
## catalog_returns / catalog_sales / inventory / store_returns / store_sales / web_returns / web_sales
export TABLE_USE_PARTITION="true"
## SET TABLE_STORAGE_OPTIONS with different options in GP/CBDB/Cloud "appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5, blocksize=1048576"
export TABLE_STORAGE_OPTIONS="WITH (appendoptimized=true, orientation=column,compresstype=zstd, compresslevel=5)"