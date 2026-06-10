#!/usr/bin/env bash
#gpconfig -c gp_resource_manager -v group
#gpconfig -c gp_resource_group_memory_limit -v 0.9
#gpconfig -c gp_resgroup_memory_policy -v auto
#gpconfig -c gp_workfile_compression -v off

gpconfig -c runaway_detector_activation_percent -v 100
gpconfig -c optimizer_enable_associativity -v on

gpconfig -c gp_interconnect_queue_depth -v 16
gpconfig -c gp_interconnect_snd_queue_depth -v 16

gpconfig -c gp_vmem_protect_limit -v 16384
gpconfig -c max_statement_mem -v 16384000
#gpconfig -c statement_mem -v 10GB

gpconfig -c work_mem -v 512000

#gpconfig -c gp_fts_probe_timeout -v 300
#gpconfig -c gp_fts_probe_interval -v 300
#gpconfig -c gp_segment_connect_timeout -m 1800 -v 1800

gpconfig -c gp_autostats_mode -v 'none'
gpconfig -c autovacuum -v off
gpconfig -c max_connections -m 100 -v 500
gpconfig -c max_prepared_transactions -v 100


# the following for mirrorless configuration only
# gpconfig -c gp_dispatch_keepalives_idle -v 20
# gpconfig -c gp_dispatch_keepalives_interval -v 20
# gpconfig -c gp_dispatch_keepalives_count -v 44


gpconfig -c gp_enable_runtime_filter_pushdown -v on
gpconfig -c gp_appendonly_insert_files -v 0
gpconfig -c gp_interconnect_fc_method -v loss_advance
gpconfig -c pg_gophermeta.register_gophermeta -v off
gpconfig -c optimizer_force_split_window_function -v on

# The following are for special scenarios, DONNOT enable them unless you know what you are doing
# gpconfig -c fixeddecimal.enable_optimizer -v on
gpconfig -c optimizer_enable_parallel_append -v on
gpconfig -c enable_parallel -v on
gpconfig -c max_parallel_workers_per_gather -v 2
gpconfig -c min_parallel_table_scan_size -v 0
gpconfig -c parallel_setup_cost -v 0
gpconfig -c pax.enable_prefetch -v on
gpconfig -c pax.enable_iouring -v on







#psql ${PSQL_OPTIONS} -f set_resource_group.sql template1
