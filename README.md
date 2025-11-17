# Decision Support Benchmark for Cloudberry Database

[![TPC-DS](https://img.shields.io/badge/TPC--DS-v4.0.0-blue)](http://www.tpc.org/tpcds/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

A comprehensive tool for running TPC-DS benchmarks on Cloudberry / HashData / Greenplum / PostgreSQL. Originally derived from [Pivotal TPC-DS](https://github.com/pivotal/TPC-DS).

## Overview

This tool provides:
- Automated TPC-DS benchmark execution
- Support for both local and cloud deployments
- Configurable data generation (1GB to 100TB)
- Customizable query execution parameters
- Detailed performance reporting

## Table of Contents
- [Decision Support Benchmark for Cloudberry Database](#decision-support-benchmark-for-cloudberry-database)
  - [Overview](#overview)
  - [Table of Contents](#table-of-contents)
  - [Quick Start](#quick-start)
    - [Guides to run test on MPP Architecture with "local" mode](#guides-to-run-test-on-mpp-architecture-with-local-mode)
    - [Guides to run test on Postgresql compatible database with "Cloud" mode](#guides-to-run-test-on-postgresql-compatible-database-with-cloud-mode)
  - [Supported TPC-DS Versions](#supported-tpc-ds-versions)
  - [Prerequisites](#prerequisites)
    - [Tested Products](#tested-products)
    - [Local Cluster Setup](#local-cluster-setup)
    - [Remote Client Setup](#remote-client-setup)
    - [Introduction to TPC-DS-Toolkit Process.](#introduction-to-tpc-ds-toolkit-process)
    - [TPC-DS Tools Dependencies](#tpc-ds-tools-dependencies)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Configuration](#configuration)
    - [Environment Options](#environment-options)
    - [Benchmark Options](#benchmark-options)
    - [Storage Options](#storage-options)
    - [Step Control Options](#step-control-options)
    - [Miscellaneous Options](#miscellaneous-options)
  - [Performance Tuning](#performance-tuning)
  - [Benchmark Modifications](#benchmark-modifications)
    - [1. Date Interval Syntax Changes](#1-date-interval-syntax-changes)
    - [2. ORDER BY Column Alias Fixes](#2-order-by-column-alias-fixes)
    - [3. Column Reference Corrections](#3-column-reference-corrections)
    - [4. Table Alias Additions](#4-table-alias-additions)
    - [5. Result Limiting](#5-result-limiting)
  - [Troubleshooting](#troubleshooting)
    - [Common Issues and Solutions](#common-issues-and-solutions)
    - [Logs and Diagnostics](#logs-and-diagnostics)
  - [Contributing](#contributing)
  - [License](#license)

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/cloudberry-contrib/TPC-DS-Toolkit.git
cd TPC-DS-Toolkit

# 2. Configure your environment
vim tpcds_variables.sh

# 3. Run the benchmark
./run.sh
```

### Guides to run test on MPP Architecture with "local" mode

Fit for products: Cloudberry / Greenplum / SynxDB 4.x / HashData Lightning.

Please refer to the [QuickStartLocal.md](tpcds_tools/QuickStartLocal.md) for more details.

### Guides to run test on Postgresql compatible database with "Cloud" mode

Fit for products: Any products that is compatible with Postgresql using `psql` clients. Including Hashdata Enterprise, SynxDB Elastic.

Please refer to the [QuickStartCloud.md](tpcds_tools/QuickStartCloud.md) for more details.


## Supported TPC-DS Versions

| Version | Date | Specification |
|---------|------|---------------|
| 4.0.0 | 2023/12/15 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v4.0.0.pdf) |
| 3.2.0 | 2021/06/15 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v3.2.0.pdf) |
| 2.1.0 | 2015/11/12 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v2.1.0.pdf) |
| 1.3.1 | 2015/02/19 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v1.3.1.pdf) |

This tool uses TPC-DS 4.0.0 as of the latest version.

## Prerequisites

This tool is built with shell scripts and has been tested primarily on CentOS-based operating systems. To accommodate different products, various options are available to choose storage types, partitions, optimizer settings, and distribution policies. Please review the `tpcds_variables.sh` for detailed configuration options for different models and products.

### Tested Products
- Cloudberry 1.x / Cloudberry 2.X
- HashData Enterprise / HashData Lightning
- Greenplum 4.x / Greenplum 5.x / Greenplum 6.x / Greenplum 7.x
- PostgreSQL 17.X

### Local Cluster Setup
For running tests on the coordinator host:

This mode leverages the MPP architecture to use data directories of segment nodes to generate data and load data using the 'gpfdist' protocol. More resources will be utilized for data generation and loading to accelerate the test process.

1. Set `RUN_MODEL="local"` in `tpcds_variables.sh`
2. Ensure you have a running Cloudberry Database with `gpadmin` access
3. Create a `gpadmin` database
4. Configure password-less `ssh` between `mdw` (coordinator) and segment nodes (`sdw1..n`)

### Remote Client Setup  
For running tests from a remote client:

With this mode, all data will be generated on the client machine, and data will be imported into the database using the `copy` command. This mode works for HashData Cloud, Cloudberry, Greenplum, HashData Lightning, and should work for other PostgreSQL-compatible products. However, it is recommended to use `local` mode for non-Cloud MPP products.

1. Set `RUN_MODEL="cloud"` in `tpcds_variables.sh`
2. Install `psql` client with passwordless access (`.pgpass`)
3. Create `gpadmin` database with:
   ```sql
   ALTER ROLE gpadmin SET warehouse=testforcloud;
   ```
4. Configure required variables in `tpcds_variables.sh`:
   ```bash
   export RANDOM_DISTRIBUTION="true"
   export TABLE_STORAGE_OPTIONS="compresstype=zstd, compresslevel=5"
   export CUSTOM_GEN_PATH="/tmp/dsbenchmark" 
   export GEN_DATA_PARALLEL="2"
   ```
> The following conventions are used in this document: mdw for the coordinator node, and sdw1..n for segment nodes.

### Introduction to TPC-DS-Toolkit Process.

TPC-DS Tool Execution Process:
1. Compile TPC-DS tools
   - Build the benchmark toolkit from source code
2. Generate test data
   - Create datasets using dsdgen based on specified scale factor
3. Initialize cluster
   - Provision and configure the database cluster environment
4. Initialize database objects
   - Create schemas, tables, and indexes required for TPC-DS
5. Load data
   - Import generated datasets into the database.
6. Analyze tables
   - Compute table statistics for optimal query performance
7. Single user test (Power test)
   - Execute all 99 queries sequentially to measure single-threaded performance
8. Single user reports
   - Generate the result for single user test.
9. Multi users test (Throughput test)
   - Execute multiple queries concurrently to measure system throughput capacity.
10. Multi user reports
    - Generate the result for multi users test.
11. Final score
    - Generate performance metric combining power and throughput tests.


### TPC-DS Tools Dependencies

Install the dependencies on `mdw` for compiling the `dsdgen` (data generation) and `dsqgen` (query generation) tools:

```bash
ssh root@mdw
yum -y install gcc make byacc flex unzip
```

The original source code is from the [TPC website](http://tpc.org/tpc_documents_current_versions/current_specifications5.asp).

## Installation

Simply clone the repository with Git or download the source code from GitHub:

```bash
ssh gpadmin@mdw
git clone https://github.com/cloudberry-contrib/TPC-DS-Toolkit.git
```

Place the folder under `/home/gpadmin/` and change ownership to gpadmin:

```bash
chown -R gpadmin:gpadmin TPC-DS-Toolkit
```

## Usage

To run the benchmark, login as `gpadmin` on the coordinator node (`mdw`):

```bash
ssh gpadmin@mdw
cd ~/TPC-DS-Toolkit
./run.sh
```

By default, this will run a scale 1 (1GB) benchmark with 1 concurrent user, from data generation through to score computation, in the background. Logs will be stored with the name `tpcds_<timestamp>.log` in the `~/TPC-DS-Toolkit` directory.

## Configuration

The benchmark is controlled through the `tpcds_variables.sh` file. Here are the key configuration sections:

### Environment Options
```bash
# Core settings
export ADMIN_USER="gpadmin"
export BENCH_ROLE="dsbench" 
export DB_SCHEMA_NAME="tpcds"  # Database schema to use for all TPC-DS data tables  
export RUN_MODEL="cloud"    # "local" or "cloud"

# Remote cluster connection
export PSQL_OPTIONS="-h <host> -p <port>"
export CUSTOM_GEN_PATH="/tmp/dsbenchmark"  # Location for data generation, separated by space for multiple paths.
export GEN_DATA_PARALLEL="2"             # Number of parallel data generation processes for each path.

```

### Benchmark Options
```bash
# Scale and concurrency 
export GEN_DATA_SCALE="1"    # 1 = 1GB, 1000 = 1TB, 3000 = 3TB
export MULTI_USER_COUNT="2"  # Number of concurrent users during throughput tests

# For large scale tests, consider:
# - 3TB: GEN_DATA_SCALE="3000" with MULTI_USER_COUNT="5"
# - 10TB: GEN_DATA_SCALE="10000" with MULTI_USER_COUNT="7"
# - 30TB: GEN_DATA_SCALE="30000" with MULTI_USER_COUNT="10"
```

### Storage Options  
```bash
# Table format and compression options
export TABLE_ACCESS_METHOD="USING ao_column"  # Available options:
                                       # - heap: Classic row storage
                                       # - ao_row: Append-optimized row storage
                                       # - ao_column: Append-optimized columnar storage
                                       # - pax: PAX storage format (Cloudberry 2.0/HashData Lightning only)

export TABLE_STORAGE_OPTIONS="WITH (compresstype=zstd, compresslevel=5)"  # Compression settings:
                                                                           # - zstd: Best compression ratio
                                                                           # - compresslevel: 1-19 (higher=better compression)

# Table partitioning for 7 large tables:
# catalog_returns, catalog_sales, inventory, store_returns, store_sales, web_returns, web_sales
export TABLE_USE_PARTITION="true"
```

**Note**: 
- `TABLE_ACCESS_METHOD`: Default to non-value to be compatible with HashData Cloud and early Greenplum versions. Should be set to `USING ao_column` for Cloudberry or Greenplum. `USING PAX` is available for Cloudberry 2.0 and HashData Lightning.
- For earlier Greenplum products without `TABLE_ACCESS_METHOD` support, use full options: `appendoptimized=true, orientation=column, compresstype=zlib, compresslevel=5, blocksize=1048576` 
- Distribution policies are defined in `TPC-DS-Toolkit/03_ddl/distribution.txt`. With products supporting `REPLICATED` policy, 14 tables use `REPLICATED` distribution by default. For early Greenplum products without `REPLICATED` policy support, see `TPC-DS-Toolkit/03_ddl/distribution_original.txt`.
- Table partition definitions are in `TPC-DS-Toolkit/03_ddl/*.sql.partition`. When using table partitioning along with column-oriented tables, if the block size is set to a large value, it might cause high memory consumption and result in out-of-memory errors. In that case, reduce the block size or the number of partitions.

### Step Control Options
```bash
# Benchmark execution steps
# 1. Setup and compilation
export RUN_COMPILE_TPCDS="true"  # Compile data/query generators (one-time)
export RUN_INIT="true"           # Initialize cluster settings

# 2. Data generation and loading
export RUN_GEN_DATA="true"       # Generate test data
export GEN_NEW_DATA="true"       # Generate new data vs reusing existing data
export RUN_DDL="true"            # Create database schemas/tables
export DROP_EXISTING_TABLES="true" # Drop existing tables before creating new ones
export RUN_LOAD="true"           # Load generated data
export LOAD_PARALLEL="2"         # Number of parallel processes to load data (max 24)
export TRUNCATE_TABLES="true"    # Truncate existing tables before loading data

# 3. Statistics and optimization
export RUN_ANALYZE="true"        # Compute table statistics for query optimization
export RUN_ANALYZE_PARALLEL="5"  # Number of parallel processes for analyze (max 24)

# 4. Query execution
export RUN_SQL="true"                 # Run power test queries
export RUN_QGEN="true"                # Generate queries for TPC-DS benchmark
export UNIFY_QGEN_SEED="true"         # Use unified seed for query generation
export QUERY_INTERVAL="0"             # Wait time between each query execution
export ON_ERROR_STOP="0"              # Stop on error flag (1 to stop)
export RUN_SINGLE_USER_REPORTS="true" # Upload single-user test results
export RUN_MULTI_USER="false"         # Run throughput test queries
export RUN_MULTI_USER_QGEN="true"     # Generate queries for multi-user test
export RUN_MULTI_USER_REPORTS="false" # Upload multi-user test results
export RUN_SCORE="false"              # Compute final benchmark score
```

There are multiple steps in running the benchmark, controlled by these variables:

| Variable                  | Default | Description |
|---------------------------|---------|-------------|
| `RUN_COMPILE_TPCDS`       | `true`  | Compiles `dsdgen` and `dsqgen`. Usually only needs to be done once. |
| `RUN_GEN_DATA`            | `true`  | Generates flat files for the benchmark in parallel on all segment nodes. Files are stored under the `${PGDATA}/dsbenchmark` directory. |
| `GEN_NEW_DATA`            | `true`  | Controls whether to generate new data or reuse existing data. Only effective when `RUN_GEN_DATA` is true. |
| `RUN_INIT`                | `true`  | Sets up GUCs for the database and records segment configurations. Required after cluster reconfiguration. |
| `RUN_DDL`                 | `true`  | Recreates schemas and tables (including external tables for loading). Set to `false` to keep existing data. |
| `DROP_EXISTING_TABLES`    | `true`  | Controls whether to drop existing tables before creating new ones. Only effective when `RUN_DDL` is true. |
| `RUN_LOAD`                | `true`  | Loads data from flat files into tables. |
| `LOAD_PARALLEL`           | `2`     | Number of parallel processes to load data (maximum 24). |
| `TRUNCATE_TABLES`         | `true`  | Truncate existing tables before loading data. |
| `RUN_ANALYZE`             | `true`  | Computes table statistics for optimal query performance. |
| `RUN_ANALYZE_PARALLEL`    | `5`     | Number of parallel processes for analyze (maximum 24). |
| `RUN_SQL`                 | `true`  | Runs the power test of the benchmark. |
| `RUN_QGEN`                | `true`  | Generate queries for the TPC-DS benchmark. |
| `UNIFY_QGEN_SEED`         | `true`  | Use unified seed for query generation. |
| `QUERY_INTERVAL`          | `0`     | Wait time between each query execution. Set to 1 if you want to stop when an error occurs. |
| `ON_ERROR_STOP`           | `0`     | Stop on error flag (1 to stop). |
| `RUN_SINGLE_USER_REPORTS` | `true`  | Generate results to the database under the schema `tpcds_reports`. Required for the `RUN_SCORE` step. |
| `RUN_MULTI_USER`          | `false` | Runs the throughput test of the benchmark. This generates multiple query streams using `dsqgen`, which samples the database to find proper filters. For very large databases with many streams, this process can take hours just to generate the queries. |
| `RUN_MULTI_USER_QGEN`     | `true`  | Generate queries for multi-user test. |
| `RUN_MULTI_USER_REPORTS`  | `false` | Generate multi-user results to the database. |
| `RUN_SCORE`               | `false` | Computes the final `QphDS` score based on the benchmark standard. |

**WARNING**: TPC-DS does not rely on the log folder to determine which steps to run or skip. It will only run the steps that are explicitly set to `true` in the `tpcds_variables.sh` file. If any necessary step is set to `false` but has never been executed before, the script will abort when it tries to access data that doesn't exist.

### Miscellaneous Options

```bash
# Misc options
export SINGLE_USER_ITERATIONS="1"      # Number of times to run the power test
export EXPLAIN_ANALYZE="false"         # Set to true for query plan analysis
export RANDOM_DISTRIBUTION="false"     # Use random distribution for fact tables
export ENABLE_VECTORIZATION="off"      # Set to on/off to enable vectorization
export STATEMENT_MEM="2GB"             # Memory per statement for single-user test
export STATEMENT_MEM_MULTI_USER="1GB"  # Memory per statement for multi-user test
export GPFDIST_LOCATION="p"            # Where gpfdist will run: p (primary) or m (mirror)
export OSVERSION=$(uname)
export ADMIN_USER=$(whoami)
export ADMIN_HOME=$(eval echo ${HOME}/${ADMIN_USER})
export MASTER_HOST=$(hostname -s)
```

Key options explained:

- `EXPLAIN_ANALYZE`: When set to `true`, executes queries with `EXPLAIN ANALYZE` to see query plans, costs, and memory usage. For debugging only, as it affects benchmark results.
- `RANDOM_DISTRIBUTION`: When set to `true`, fact tables are distributed randomly rather than using pre-defined distribution columns. Recommended for Cloud products.
- `SINGLE_USER_ITERATION`: Controls how many times the power test runs. The fastest query time from multiple runs is used for final scoring.
- `STATEMENT_MEM`: Sets memory per statement for single-user tests (should be less than `gp_vmem_protect_limit`).
- `STATEMENT_MEM_MULTI_USER`: Sets memory per statement for multi-user tests (note: `STATEMENT_MEM_MULTI_USER` × `MULTI_USER_COUNT` should be less than `gp_vmem_protect_limit`).
- `ENABLE_VECTORIZATION`: Set to `on` to enable vectorized computing for better performance (supported in Lightning 1.5.3+). Only works with AO column and PAX table formats.

## Performance Tuning

For optimal performance:

1. **Memory Settings**
   ```bash
   # Recommended for 8GB+ RAM per segment node cluster
   export STATEMENT_MEM="8GB"
   # Should be set to STATEMENT_MEM / MULTI_USER_COUNT
   export STATEMENT_MEM_MULTI_USER="4GB"
   ```

2. **Storage Optimization**
   ```bash
   # For best compression ratio
   export TABLE_ACCESS_METHOD="USING ao_column"
   export TABLE_STORAGE_OPTIONS="WITH (compresstype=zstd, compresslevel=9)"
   # Use partitioned tables for better query performance
   export TABLE_USE_PARTITION="true"
   ```

3. **Concurrency Tuning**
   ```bash
   # Adjust based on available CPU cores
   export GEN_DATA_PARALLEL="$(nproc)"
   export MULTI_USER_COUNT="$(( $(nproc) / 2 ))"
   ```

4. **Enable Vectorization** (for supported systems)
   ```bash
   export ENABLE_VECTORIZATION="on"
   ```

5. **Optimizer Settings** (for supported systems)

   ```bash
   # Adjust optimizer settings in 01_gen_data/optimizer.txt
   # Turn ORCA on/off for each queries by setting in this file
   # After changing the settings, make sure to run the QGEN to generate the queries with the new settings.
   ```

## Benchmark Modifications

The TPC-DS queries were modified in the following ways to ensure compatibility:

### 1. Date Interval Syntax Changes
Changed date addition syntax from:
```sql
and (cast('2000-02-28' as date) + 30 days)
```
To:
```sql
and (cast('2000-02-28' as date) + '30 days'::interval)
```
Affected queries: 5, 12, 16, 20, 21, 32, 37, 40, 77, 80, 82, 92, 94, 95, and 98.

### 2. ORDER BY Column Alias Fixes
Added subqueries for ORDER BY clauses with column aliases:
```sql
-- New version with subquery
select * from (
  -- Original query
) AS sub
order by
  lochierarchy desc
  ,case when lochierarchy = 0 then s_state end
  ,rank_within_parent
limit 100;
```
Affected queries: 36 and 70.

### 3. Column Reference Corrections
Modified query templates to exclude columns not found in the query, specifically in common table expressions where alias columns were used in dynamic filters.
Affected query: 86.

### 4. Table Alias Additions
Added table aliases to improve query parser compatibility.
Affected queries: 2, 14, and 23.

### 5. Result Limiting
Added `LIMIT 100` to queries that could produce very large result sets.
Affected queries: 64, 34, and 71.

## Troubleshooting

### Common Issues and Solutions

1. **Missing or Invalid Environment Variables**  
   Ensure all required environment variables in `tpcds_variables.sh` are set correctly. If any variable is missing or invalid, the script will abort and display the problematic variable name. Double-check the following key variables:
   - `RUN_MODEL`
   - `GEN_DATA_SCALE`
   - `TABLE_ACCESS_METHOD`
   - `PSQL_OPTIONS`

2. **Permission Errors**  
   - Verify ownership: `chown -R gpadmin:gpadmin /home/gpadmin/TPC-DS-Toolkit`
   - Ensure `gpadmin` has proper database access permissions

3. **Data Generation Failures**  
   - Confirm successful compilation of `dsdgen`
   - Verify `CUSTOM_GEN_PATH` points to a valid, writable directory
   - Check available disk space

4. **Query Execution Errors**  
   - Ensure tables and schemas exist (set `RUN_DDL=true` on first run)
   - Look for syntax errors in modified queries
   - Verify database connectivity

5. **Performance Issues**  
   - Adjust memory settings based on system resources
   - Enable vectorization if supported
   - Use appropriate storage options for your workload
   - Consider partitioning for large tables
   - Adjust database parameters as referred to: [set_gucs](tpcds_tools/set_gucs.sh)

### Logs and Diagnostics

For detailed diagnostics, examine:
- Main log file: `tpcds_<timestamp>.log` in `~/TPC-DS-Toolkit`
- Database server logs
- System resource utilization during test runs

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.