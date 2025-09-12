# TPC-DS Benchmark Toolkit

[![TPC-DS](https://img.shields.io/badge/TPC--DS-v3.2.0-blue)](http://www.tpc.org/tpcds/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

A comprehensive tool for running TPC-DS benchmarks on Cloudberry Database, Greenplum, HashData, and PostgreSQL-compatible databases. Originally derived from [Pivotal TPC-DS](https://github.com/pivotal/TPC-DS).

## Overview

This toolkit provides automated TPC-DS benchmark execution with:
- Support for both local (coordinator-host) and cloud (remote-client) deployments
- Configurable data generation from 1GB to 100TB scale factors
- Customizable query execution parameters and storage options
- Detailed performance reporting and scoring

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

### Deployment Modes

**Local Mode** (`RUN_MODEL="local"`):
- Runs on coordinator host leveraging MPP architecture
- Uses gpfdist protocol for parallel data loading
- Recommended for Cloudberry, Greenplum, HashData Lightning, SynxDB
- See [QuickStartLocal.md](tpcds_tools/QuickStartLocal.md)

**Cloud Mode** (`RUN_MODEL="cloud"`):
- Runs from remote client using psql connections
- Uses COPY command for data loading
- Compatible with PostgreSQL and cloud databases
- See [QuickStartCloud.md](tpcds_tools/QuickStartCloud.md)

## Supported TPC-DS Versions

| Version | Date | Specification |
|---------|------|---------------|
| 3.2.0 | 2021/06/15 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v3.2.0.pdf) |
| 2.1.0 | 2015/11/12 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v2.1.0.pdf) |
| 1.3.1 | 2015/02/19 | [PDF](http://www.tpc.org/tpc_documents_current_versions/pdf/tpc-ds_v1.3.1.pdf) |

This toolkit uses TPC-DS 3.2.0 and is currently at version 1.6.

## Prerequisites

This toolkit is built with shell scripts and supports various database products through configurable options. Review `tpcds_variables.sh` for detailed configuration options.

### Tested Products
The toolkit automatically detects and supports these database versions:
- **Cloudberry Database** (CBDB) - all versions
- **Greenplum Database** - 4.3, 5.x, 6.x, 7.x
- **HashData Enterprise** - 4.x
- **HashData Lightning** - all versions
- **SynxDB** - 1.x, 2.x, 3.x, 4.x
- **PostgreSQL** - all compatible versions

### Local Cluster Setup (Recommended for MPP)
For running tests on the coordinator host:

1. Set `RUN_MODEL="local"` in `tpcds_variables.sh`
2. Ensure running database cluster with administrative access
3. Configure password-less SSH between coordinator and segment nodes
4. Install dependencies: `gcc`, `make`, `byacc` on coordinator

### Remote Client Setup (Cloud Mode)
For running tests from a remote client:

1. Set `RUN_MODEL="cloud"` in `tpcds_variables.sh`
2. Install `psql` client with proper database connectivity
3. Configure `.pgpass` for passwordless access
4. Set appropriate client-side variables

### TPC-DS Tools Dependencies

Install compilation dependencies on CentOS/RHEL systems:
```bash
yum install -y gcc make byacc
```

## Execution Process

The benchmark follows this sequential workflow:

1. **Compile TPC-DS Tools** (`RUN_COMPILE_TPCDS`) - Builds data and query generators
2. **Generate Test Data** (`RUN_GEN_DATA`) - Creates datasets using dsdgen
3. **Initialize Cluster** (`RUN_INIT`) - Configures database settings
4. **Create Database Objects** (`RUN_DDL`) - Sets up schemas, tables, and distribution
5. **Load Data** (`RUN_LOAD`) - Imports generated data into tables
6. **Analyze Statistics** (`RUN_ANALYZE`) - Computes table statistics for optimization
7. **Power Test** (`RUN_SQL`) - Executes 99 queries sequentially
8. **Single User Reports** (`RUN_SINGLE_USER_REPORTS`) - Generates power test results
9. **Throughput Test** (`RUN_MULTI_USER`) - Runs concurrent query streams
10. **Multi User Reports** (`RUN_MULTI_USER_REPORTS`) - Generates throughput results
11. **Final Scoring** (`RUN_SCORE`) - Computes QphDS metric

> **Convention**: `mdw` refers to coordinator node, `sdw1..n` to segment nodes.

## Installation

1. Clone the repository:
```bash
git clone https://github.com/cloudberry-contrib/TPC-DS-Toolkit.git
cd TPC-DS-Toolkit
```

2. Configure environment variables in `tpcds_variables.sh`:
```bash
# Set your database connection parameters
export PGHOST="your_coordinator_host"
export PGPORT="5432"
export PGDATABASE="tpcds"
export PGUSER="gpadmin"

# Set scale factor and other benchmark parameters
export GEN_DATA_SCALE="1"  # 1 = 1GB, 1000 = 1TB
export MULTI_USER_COUNT="2" # Number of concurrent users
```

## Usage

Run the complete benchmark pipeline:
```bash
./run.sh
```

Customize execution by modifying environment variables or using step control:
```bash
# Run specific steps only
export RUN_GEN_DATA="true"
export RUN_DDL="true" 
export RUN_LOAD="true"
export RUN_SQL="false"
./run.sh

# Or disable specific steps
export RUN_ANALYZE="false"
export RUN_MULTI_USER="false"
./run.sh
```

Monitor progress through log files in the `log/` directory.

## Configuration Reference

The benchmark is configured through environment variables in `tpcds_variables.sh`. Key options include:

### Core Settings
```bash
export ADMIN_USER="gpadmin"           # OS user executing the toolkit
export BENCH_ROLE="dsbench"           # Database user for benchmark execution
export DB_SCHEMA_NAME="tpcds"         # Schema for TPC-DS tables
export RUN_MODEL="local"              # "local" (coordinator) or "cloud" (remote)
export PSQL_OPTIONS=""                # Database connection parameters
```

### Benchmark Scale
```bash
export GEN_DATA_SCALE="1"              # Scale factor: 1=1GB, 1000=1TB, 10000=10TB
export MULTI_USER_COUNT="2"           # Concurrent users for throughput test
```

### Storage Configuration
```bash
export TABLE_ACCESS_METHOD=""          # Options: "USING ao_column", "USING heap", "USING ao_row"
export TABLE_STORAGE_OPTIONS="WITH (appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5)"
export TABLE_USE_PARTITION="false"     # Enable partitioning for large tables
```

### Step Control
Control which benchmark steps to execute:
```bash
export RUN_COMPILE_TPCDS="true"       # Compile data/query generators
export RUN_GEN_DATA="true"            # Generate test data
export RUN_INIT="true"                # Initialize cluster settings
export RUN_DDL="true"                 # Create database objects
export RUN_LOAD="true"                # Load data into tables
export RUN_ANALYZE="true"             # Compute table statistics
export RUN_SQL="true"                 # Execute power test queries
export RUN_SINGLE_USER_REPORTS="true" # Generate single-user reports
export RUN_MULTI_USER="false"         # Execute throughput test
export RUN_MULTI_USER_REPORTS="false" # Generate multi-user reports
export RUN_SCORE="false"              # Compute final QphDS score
```

### Performance Tuning
```bash
export SINGLE_USER_ITERATIONS="1"     # Power test iterations
export EXPLAIN_ANALYZE="false"       # Enable query plan analysis (debug only)
export RANDOM_DISTRIBUTION="false"   # Use random distribution for fact tables
export ENABLE_VECTORIZATION="off"    # Enable vectorized execution
export STATEMENT_MEM="2GB"           # Memory per statement (single-user)
export STATEMENT_MEM_MULTI_USER="1GB" # Memory per statement (multi-user)
export LOAD_PARALLEL="2"             # Parallel data loading processes
export RUN_ANALYZE_PARALLEL="5"      # Parallel analyze processes
```

**Note**: Distribution policies are defined in `03_ddl/distribution.txt`. For databases without `REPLICATED` distribution support, use `03_ddl/distribution_original.txt`.

## Benchmark Modifications

The TPC-DS queries were modified for compatibility:

### 1. Date Interval Syntax Changes
Changed date addition syntax to use proper interval format.

### 2. ORDER BY Column Alias Fixes
Added subqueries for ORDER BY clauses with column aliases.

### 3. Column Reference Corrections
Modified query templates to exclude columns not found in the query.

### 4. Table Alias Additions
Added table aliases to improve query parser compatibility.

### 5. Result Limiting
Added `LIMIT 100` to queries that could produce very large result sets.

## Troubleshooting

### Common Issues and Solutions

1. **Missing or Invalid Environment Variables**
   Ensure all required environment variables in `tpcds_variables.sh` are set correctly.

2. **Permission Errors**
   Verify ownership and database access permissions.

3. **Data Generation Failures**
   Confirm successful compilation of `dsdgen` and verify disk space.

4. **Query Execution Errors**
   Ensure tables and schemas exist, check for syntax errors.

5. **Performance Issues**
   Adjust memory settings, enable vectorization if supported.

### Logs and Diagnostics

For detailed diagnostics, examine:
- Main log file: `tpcds_<timestamp>.log` in the toolkit directory
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