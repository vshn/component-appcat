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


local defaultDB = 'postgres';
local defaultUser = 'postgres';
local defaultPort = '5432';

local certificateSecretName = 'tls-certificate';

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';
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

local sa = kube.ServiceAccount('stackgres-sgconfig-restapi-patcher') {
  metadata+: {
    namespace: params.stackgres.namespace,
  },
};

local role = kube.Role('stackgres-sgconfig-restapi-patcher') {
  metadata+: {
    namespace: params.stackgres.namespace,
  },
  rules: [
    {
      apiGroups: [
        'stackgres.io',
      ],
      resources: [
        'sgconfigs',
      ],
      verbs: [
        'get',
        'list',
        'watch',
        'patch',
      ],
    },
  ],
};

local rolebinding = kube.RoleBinding('stackgres-sgconfig-restapi-patcher') {
  metadata+: {
    namespace: params.stackgres.namespace,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: 'stackgres-sgconfig-restapi-patcher',
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'stackgres-sgconfig-restapi-patcher',
    },
  ],
};

local stackgresOperatorConfigPatch = kube.Job('stackgres-sgconfig-restapi-patcher') {
  metadata+: {
    namespace: params.stackgres.namespace,
  },
  spec+: {
    template+: {
      spec+: {
        restartPolicy: 'Never',
        serviceAccountName: 'stackgres-sgconfig-restapi-patcher',
        containers: [
          {
            name: 'patch-restapi',
            image: params.images.kubectl.registry + '/' + params.images.kubectl.image + ':' + params.images.kubectl.tag,
            command: [
              'sh',
              '-c',
            ],
            args: [
              'cat <<EOF | kubectl -n ${TARGET_NAMESPACE} patch sgconfig stackgres-operator --type merge -p "$(cat)"\nspec:\n  restapi:\n    image:\n      name: stackgres/restapi\n      pullPolicy: IfNotPresent\n    name: stackgres-restapi\nEOF',
            ],
            env: [
              {
                name: 'TARGET_NAMESPACE',
                value: params.stackgres.namespace,
              },
            ],
          },
        ],
      },
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
  +
  if std.length(params.stackgres.operator.resources) > 0 then
    {
      spec+: {
        config+: {
          resources: params.stackgres.operator.resources,
        },
      },
    }
  else {},
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
) + xrds.WithPlanDefaults(pgPlans, pgParams.defaultPlan);

local promRulePostgresSLA = prom.PromRuleSLA(params.services.vshn.postgres.sla, 'VSHNPostgreSQL');

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
      resources: [ 'vshnpostgresqls' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get', 'create', 'patch' ],
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
              name: 'function-appcat',
            },
            input: kube.ConfigMap('xfn-config') + {
              metadata: {
                labels: {
                  name: 'xfn-config',
                },
                name: 'xfn-config',
              },
              data: {
                      serviceName: 'postgresql',
                      imageTag: common.GetAppCatImageTag(),
                      sgNamespace: pgParams.sgNamespace,
                      externalDatabaseConnectionsEnabled: std.toString(params.services.vshn.externalDatabaseConnectionsEnabled),
                      quotasEnabled: std.toString(params.services.vshn.quotasEnabled),
                      plans: std.toString(pgPlans),
                      sideCars: std.toString(pgParams.sideCars),
                      initContainers: std.toString(pgParams.initContainers),
                      keepMetrics: std.toString(keepMetrics),
                      controlNamespace: params.services.controlNamespace,
                      ownerKind: xrd.spec.names.kind,
                      ownerGroup: xrd.spec.group,
                      ownerVersion: xrd.spec.versions[0].name,
                      bucketRegion: pgParams.bucket_region,
                      bucketEndpoint: pgParams.bucket_endpoint,
                      isOpenshift: std.toString(isOpenshift),
                      sliNamespace: params.slos.namespace,
                      salesOrder: if appuioManaged then std.toString(params.billing.salesOrder) else '',
                      crossplaneNamespace: params.crossplane.namespace,
                    } + std.get(pgParams, 'additionalInputs', default={}, inc_hidden=true)
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

if params.services.vshn.enabled && pgParams.enabled && vars.isSingleOrControlPlaneCluster then
  assert std.length(pgParams.bucket_region) != 0 : 'appcat.services.vshn.postgres.bucket_region is empty';
  assert std.length(pgParams.bucket_endpoint) != 0 : 'appcat.services.vshn.postgres.bucket_endpoint is empty';
  {
    '20_xrd_vshn_postgres': xrd,
    '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
    '20_role_vshn_postgresrestore': [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
    '20_plans_vshn_postgresql': plansCM,
    '21_composition_vshn_postgres': composition,
    '22_prom_rule_sla_postgres': promRulePostgresSLA,
    [if isOpenshift then '21_openshift_template_postgresql_vshn']: osTemplate,
    [if isOpenshift then '10_stackgres_openshift_operator_ns']: stackgresOperatorNs,
    [if isOpenshift then '11_stackgres_openshift_operator']: std.prune(stackgresOperator),
    [if isOpenshift then '12_stackgres_openshift_operator_netpol']: stackgresNetworkPolicy,
    [if isOpenshift then '13_stackgres_openshift_operator_restapi']: [ sa, role, rolebinding, stackgresOperatorConfigPatch ],
    [if params.slos.enabled && params.services.vshn.enabled && params.services.vshn.postgres.enabled then 'sli_exporter/90_slo_vshn_postgresql']: slos.Get('vshn-postgresql'),
    [if params.slos.enabled && params.services.vshn.enabled && params.services.vshn.postgres.enabled then 'sli_exporter/90_slo_vshn_postgresql_ha']: slos.Get('vshn-postgresql-ha'),
    [if params.services.vshn.enabled && params.services.vshn.postgres.enabled then 'sli_exporter/90_VSHNPostgreSQL_Opsgenie']: opsgenieRules.GenGenericAlertingRule('VSHNPostgreSQL'),

  } else {}
