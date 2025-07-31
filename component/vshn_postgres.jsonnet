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

local isBestEffort = !std.member([ 'guaranteed_availability', 'premium' ], inv.parameters.facts.service_level);

local operatorlib = import 'lib/openshift4-operators.libsonnet';

local stackgresOperatorNs = kube.Namespace(params.stackgres.namespace) {
  metadata+: {
    labels+: {
      // include namespace in cluster monitoring
      'openshift.io/cluster-monitoring': 'true',
      // ignore namespace in user-workload monitoring
      'openshift.io/user-monitoring': 'false',
    },
    annotations+: {
      'openshift.io/node-selector': '',
    },
  },
};

local stackgresNetworkPolicy = kube.NetworkPolicy('allow-stackgres-api') + {
  metadata+: {
    namespace: params.stackgres.namespace,
  },
  spec+: {
    policyTypes: [ 'Ingress' ],
    podSelector: {
      matchLabels: {
        app: 'StackGresConfig',
      },
    },
    ingress: [
      {
        from: [
          {
            namespaceSelector: {
              matchLabels: {
                'appcat.vshn.io/servicename': 'postgresql-standalone',
              },
            },
          },
          {
            namespaceSelector: {
              matchLabels: {
                name: 'syn-crossplane',
              },
            },
          },
        ],
      },
    ],
  },
};

local stackgresOperator = [
  operatorlib.OperatorGroup(params.stackgres.namespace) {
    metadata+: {
      namespace: params.stackgres.namespace,
    },
  },
  operatorlib.namespacedSubscription(
    params.stackgres.namespace,
    'stackgres',
    params.stackgres.operator.channel,
    'redhat-marketplace',
    installPlanApproval=params.stackgres.operator.installPlanApproval,
  )
  + {
    spec+: {
      config+: {
        [if std.length(params.stackgres.operator.resources) > 0 then 'resources']: params.stackgres.operator.resources,
        env: [
          { name: 'APP_OPTS', value: '-Dquarkus.vertx.max-worker-execute-time=5000' },
          { name: 'JAVA_OPTS', value: '-Dquarkus.vertx.max-worker-execute-time=5000' },
          { name: 'RECONCILIATION_PRIORITY_TIMEOUT', value: '50' },
          { name: 'RECONCILIATION_CACHE_EXPIRATION', value: '30' },
          { name: 'RECONCILIATION_CACHE_SIZE', value: '5000' },
          { name: 'PATRONI_CTL_TIMEOUT', value: '10' },
        ],
      },
    },
  },
];

// Filter out disabled plans
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
              'xvshnpostgresqls.vshn.appcat.vshn.io',
              xrds.LoadCRD('vshn.appcat.vshn.io_vshnpostgresqls.yaml', params.images.appcat.tag),
              defaultComposition='vshnpostgres.vshn.appcat.vshn.io',
              connectionSecretKeys=connectionSecretKeys,
            )
            + xrds.WithPlanDefaults(pgPlans, pgParams.defaultPlan)
            + xrds.FilterOutGuaraanteed(isBestEffort)
            + xrds.WithServiceID(serviceName);

local promRulePostgresSLA = prom.PromRecordingRuleSLA(params.services.vshn.postgres.sla, 'VSHNPostgreSQL');

local restoreServiceAccount = kube.ServiceAccount('copyserviceaccount') + {
  metadata+: {
    namespace: params.services.controlNamespace,
  },
};

local restoreRoleName = 'crossplane:appcat:job:postgres:copybackups';
local restoreRole = kube.ClusterRole(restoreRoleName) {
  rules: [
    {
      apiGroups: [ 'stackgres.io' ],
      resources: [ 'sgbackups', 'sgobjectstorages' ],
      verbs: [ 'get', 'list', 'create' ],
    },
    {
      apiGroups: [ 'vshn.appcat.vshn.io' ],
      resources: [ 'vshnkeycloaks', 'xvshnkeycloaks', 'vshnpostgresqls', 'xvshnpostgresqls' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get', 'create', 'patch' ],
    },
  ],
};

local additionalMaintenanceClusterRoleName = 'crossplane:appcat:job:postgres:maintenance';
local maintenanceClusterRole = kube.ClusterRole(additionalMaintenanceClusterRoleName) {
  rules+: [
    {
      apiGroups: [ 'apiextensions.crossplane.io' ],
      resources: [ 'compositionrevisions' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ 'vshn.appcat.vshn.io' ],
      resources: [ 'xvshnpostgresqls', 'vshnpostgresqls' ],
      verbs: [ 'get', 'update' ],
    },
  ],
};

local restoreClusterRoleBinding = kube.ClusterRoleBinding('appcat:job:postgres:copybackup') + {
  roleRef_: restoreRole,
  subjects_: [ restoreServiceAccount ],
};


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

local composition =
  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'vshnpostgres.vshn.appcat.vshn.io') +
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

// OpenShift template configuration
local templateObject = kube._Object('vshn.appcat.vshn.io/v1', 'VSHNPostgreSQL', '${INSTANCE_NAME}') + {
  spec: {
    parameters: {
      service: {
        majorVersion: '${MAJOR_VERSION}',
      },
      size: {
        plan: '${PLAN}',
      },
    },
    writeConnectionSecretToRef: {
      name: '${SECRET_NAME}',
    },
  },
};

local templateDescription = 'PostgreSQL is a powerful, open source object-relational database system that uses and extends the SQL language combined with many features that safely store and scale the most complicated data workloads. The origins of PostgreSQL date back to 1986 as part of the POSTGRES project at the University of California at Berkeley and has more than 30 years of active development on the core platform.';
local templateMessage = 'Your PostgreSQL by VSHN instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('postgresqlbyvshn',
                           'PostgreSQL',
                           templateDescription,
                           'icon-postgresql',
                           'database,sql,postgresql',
                           templateMessage,
                           'VSHN',
                           'https://vs.hn/vshn-postgresql') + {
    objects: [
      templateObject,
    ],
    parameters: [
      {
        name: 'PLAN',
        value: 'standard-4',
      },
      {
        name: 'SECRET_NAME',
        value: 'postgresql-credentials',
      },
      {
        name: 'INSTANCE_NAME',
      },
      {
        name: 'MAJOR_VERSION',
        value: '15',
      },
    ],
  };

local plansCM = kube.ConfigMap('vshnpostgresqlplans') + {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    plans: std.toString(pgPlans),
    sideCars: std.toString(pgParams.sideCars),
  },
};

local appcatFuncRoleBinding = kube.RoleBinding('appcat-function') + {
  metadata+: {
    namespace: pgParams.sgNamespace,
  },
  roleRef_: kube.Role('appcat-function:stackgres-restapi-admin'),
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'function-appcat',
      namespace: params.crossplane.namespace,
    },
  ],
};

local appcatFuncRole = kube.Role('appcat-function:stackgres-restapi-admin') {
  metadata+: {
    namespace: pgParams.sgNamespace,
  },
  rules+: [
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      resourceNames: [ 'stackgres-restapi-admin' ],
      verbs: [ 'get' ],
    },
  ],
};

(if params.services.vshn.enabled && pgParams.enabled && vars.isSingleOrControlPlaneCluster then
   {
     '20_xrd_vshn_postgres': xrd,
     '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
     '20_role_vshn_postgresrestore': [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
     '20_plans_vshn_postgresql': plansCM,
     '21_composition_vshn_postgres': composition,

     [if vars.isOpenshift then '21_openshift_template_postgresql_vshn']: osTemplate,
   } else {})
+ (if vars.isSingleOrServiceCluster then {
     '22_appcat_func_role': appcatFuncRole,
     '22_appcat_func_role_binding': appcatFuncRoleBinding,
     '22_appcat_postgres_maintenance_cluster_role': maintenanceClusterRole,
   } else {})
+ (if vars.isSingleOrServiceCluster && vars.isOpenshift then {
     '10_stackgres_openshift_operator_ns': stackgresOperatorNs,
     '11_stackgres_openshift_operator': std.prune(stackgresOperator),
     '12_stackgres_openshift_operator_netpol': stackgresNetworkPolicy,
   } else {})
+ if vars.isSingleOrServiceCluster then
  if params.slos.enabled && params.services.vshn.enabled && params.services.vshn.postgres.enabled then {
    'sli_exporter/70_slo_vshn_postgresql': slos.Get('vshn-postgresql'),
    'sli_exporter/80_slo_vshn_postgresql_ha': slos.Get('vshn-postgresql-ha'),
    [if params.slos.alertsEnabled then 'sli_exporter/90_VSHNPostgreSQL_Opsgenie']: opsgenieRules.GenGenericAlertingRule('VSHNPostgreSQL', promRulePostgresSLA),
  } else {}
else {}
