local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/appcat-crossplane.libsonnet';

local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local prom = import 'prometheus.libsonnet';
local slos = import 'slos.libsonnet';
local opsgenieRules = import 'vshn_alerting.jsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.vshn.postgres;
local appuioManaged = inv.parameters.appcat.appuioManaged;
local serviceName = 'postgresql';

local defaultDB = 'postgres';
local defaultUser = 'postgres';
local defaultPort = '5432';

local certificateSecretName = 'tls-certificate';

local securityContext = if vars.isOpenshift then false else true;

local isBestEffort = !std.member([ 'guaranteed_availability', 'premium' ], inv.parameters.facts.service_level);

local pgPlans = common.FilterDisabledParams(pgParams.plans);

local connectionSecretKeys = [
  'ca.crt',
  'tls.crt',
  'tls.key',
  'POSTGRESQL_URL',
  'POSTGRESQL_DB',
  'POSTGRESQL_HOST',
  'POSTGRESQL_PORT',
  'POSTGRESQL_USER',
  'POSTGRESQL_PASSWORD',
  'LOADBALANCER_IP',
];

local xrd = xrds.XRDFromCRD(
              'xvshnpostgresqlcnpgs.vshn.appcat.vshn.io',
              xrds.LoadCRD('vshn.appcat.vshn.io_vshnpostgresqlcnpgs.yaml', params.images.appcat.tag),
              defaultComposition='vshnpostgrescnpg.vshn.appcat.vshn.io',
              connectionSecretKeys=connectionSecretKeys,
            )
            + xrds.WithPlanDefaults(pgPlans, pgParams.defaultPlan)
            + xrds.FilterOutGuaraanteed(isBestEffort)
            + xrds.WithServiceID(serviceName);

local keepMetrics = [
  'pg_locks_count',
  'pg_postmaster_start_time_seconds',
  'pg_replication_lag',
  'pg_settings_effective_cache_size_bytes',
  'pg_settings_maintenance_work_mem_bytes',
  'pg_settings_max_connections',
  'pg_settings_max_parallel_workers',
  'pg_settings_max_wal_size_bytes',
  'pg_settings_max_worker_processes',
  'pg_settings_shared_buffers_bytes',
  'pg_settings_work_mem_bytes',
  'pg_stat_activity_count',
  'pg_stat_bgwriter_buffers_alloc_total',
  'pg_stat_bgwriter_buffers_backend_fsync_total',
  'pg_stat_bgwriter_buffers_backend_total',
  'pg_stat_bgwriter_buffers_checkpoint_total',
  'pg_stat_bgwriter_buffers_clean_total',
  'pg_stat_database_blks_hit',
  'pg_stat_database_blks_read',
  'pg_stat_database_conflicts',
  'pg_stat_database_deadlocks',
  'pg_stat_database_temp_bytes',
  'pg_stat_database_xact_commit',
  'pg_stat_database_xact_rollback',
  'pg_static',
  'pg_up',
  'pgbouncer_show_stats_total_xact_count',
  'pgbouncer_show_stats_totals_bytes_received',
  'pgbouncer_show_stats_totals_bytes_sent',
];

local additionalMaintenanceClusterRoleName = 'crossplane:appcat:job:postgres:maintenance';

local composition =
  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'vshnpostgresql.vshn.appcat.vshn.io') +
  common.SyncOptions +
  common.vshnMetaVshnDBaas('PostgreSQL', 'standalone', 'true', pgPlans) +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'pgsql-func',
            functionRef: {
              name: common.GetCurrentFunctionName(),
            },
            input: kube.ConfigMap('xfn-config') + {
              metadata: {
                labels: {
                  name: 'xfn-config',
                },
                name: 'xfn-config',
              },
              data: {
                      externalDatabaseConnectionsEnabled: std.toString(params.services.vshn.externalDatabaseConnectionsEnabled),
                      sideCars: std.toString(pgParams.sideCars),
                      initContainers: std.toString(pgParams.initContainers),
                      keepMetrics: std.toString(keepMetrics),
                      sgNamespace: pgParams.sgNamespace,
                      additionalMaintenanceClusterRole: additionalMaintenanceClusterRoleName,
                    } + common.GetDefaultInputs(serviceName, pgParams, pgPlans, xrd, appuioManaged)
                    + std.get(pgParams, 'additionalInputs', default={}, inc_hidden=true)
                    + common.EmailAlerting(params.services.emailAlerting)
                    + if pgParams.proxyFunction then {
                      proxyEndpoint: pgParams.grpcEndpoint,
                    } else {},
            },
          },
        ],
    },
  };

if params.services.vshn.enabled && pgParams.enabled && vars.isSingleOrControlPlaneCluster then {
  '20_xrd_vshn_postgresqlcnpg': xrd,
  '20_rbac_vshn_postgresqlcnpg': xrds.CompositeClusterRoles(xrd),
  '21_composition_vshn_postgrescnpg': composition,
} else {}
