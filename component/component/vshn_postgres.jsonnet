local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local prom = import 'prometheus.libsonnet';
local slos = import 'slos.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.vshn.postgres;

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
  ),
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
      verbs: [ 'get', 'create' ],
    },
  ],
};

local restoreClusterRoleBinding = kube.ClusterRoleBinding('appcat:job:postgres:copybackup') + {
  roleRef_: restoreRole,
  subjects_: [ restoreServiceAccount ],
};

local localca = {
  name: 'local-ca',
  base: comp.KubeObject('cert-manager.io/v1', 'Issuer') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {
                  name: '',
                  namespace: '',
                },
                spec: {
                  selfSigned: {
                    crlDistributionPoints: [],
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.localCAConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'localca'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.metadata.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local certificate = {
  name: 'certificate',
  base: comp.KubeObject('cert-manager.io/v1', 'Certificate') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {
                  name: '',
                  namespace: '',
                },
                spec: {
                  secretName: certificateSecretName,
                  duration: '87600h',
                  renewBefore: '2400h',
                  subject: {
                    organizations: [
                      'vshn-appcat',
                    ],
                  },
                  isCA: false,
                  privateKey: {
                    algorithm: 'RSA',
                    encoding: 'PKCS1',
                    size: 4096,
                  },
                  usages: [
                    'server auth',
                    'client auth',
                  ],
                  dnsNames: [
                    'vshn.appcat.vshn.ch',
                  ],
                  issuerRef: {
                    name: '',
                    kind: 'Issuer',
                    group: 'cert-manager.io',
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.certificateConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'certificate'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.metadata.name'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.spec.issuerRef.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),

    // We should actually set the dns name...
    comp.CombineCompositeFromTwoFieldPaths('metadata.name', 'metadata.name', 'spec.forProvider.manifest.spec.dnsNames[0]', '%s.vshn-postgresql-%s.svc.cluster.local'),
    comp.CombineCompositeFromTwoFieldPaths('metadata.name', 'metadata.name', 'spec.forProvider.manifest.spec.dnsNames[1]', '%s.vshn-postgresql-%s.svc'),
  ],
};

local sgInstanceProfile = {
  name: 'profile',
  base: comp.KubeObject('stackgres.io/v1', 'SGInstanceProfile') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {},
                spec: {
                  cpu: '',
                  memory: '',
                  requests: {
                    cpu: null,
                    memory: null,
                    containers: {
                      'backup.create-backup': {
                        cpu: pgParams.sideCars.createBackup.requests.cpu,
                        memory: pgParams.sideCars.createBackup.requests.memory,
                      },
                      'cluster-controller': {
                        cpu: pgParams.sideCars.clusterController.requests.cpu,
                        memory: pgParams.sideCars.clusterController.requests.memory,
                      },
                      'dbops.run-dbops': {
                        cpu: pgParams.sideCars.runDbops.requests.cpu,
                        memory: pgParams.sideCars.runDbops.requests.memory,
                      },
                      'dbops.set-dbops-result': {
                        cpu: pgParams.sideCars.setDbopsResult.requests.cpu,
                        memory: pgParams.sideCars.setDbopsResult.requests.memory,
                      },
                      envoy: {
                        cpu: pgParams.sideCars.envoy.requests.cpu,
                        memory: pgParams.sideCars.envoy.requests.memory,
                      },
                      pgbouncer: {
                        cpu: pgParams.sideCars.pgbouncer.requests.cpu,
                        memory: pgParams.sideCars.pgbouncer.requests.memory,
                      },
                      'postgres-util': {
                        cpu: pgParams.sideCars.postgresUtil.requests.cpu,
                        memory: pgParams.sideCars.postgresUtil.requests.memory,
                      },
                      'prometheus-postgres-exporter': {
                        cpu: pgParams.sideCars.prometheusPostgresExporter.requests.cpu,
                        memory: pgParams.sideCars.prometheusPostgresExporter.requests.memory,
                      },
                    },
                    initContainers: {
                      'pgbouncer-auth-file': {
                        cpu: pgParams.initContainers.pgbouncerAuthFile.requests.cpu,
                        memory: pgParams.initContainers.pgbouncerAuthFile.requests.memory,
                      },
                      'relocate-binaries': {
                        cpu: pgParams.initContainers.relocateBinaries.requests.cpu,
                        memory: pgParams.initContainers.relocateBinaries.requests.memory,
                      },
                      'setup-scripts': {
                        cpu: pgParams.initContainers.setupScripts.requests.cpu,
                        memory: pgParams.initContainers.setupScripts.requests.memory,
                      },
                      'setup-arbitrary-user': {
                        cpu: pgParams.initContainers.setupArbitraryUser.requests.cpu,
                        memory: pgParams.initContainers.setupArbitraryUser.requests.memory,
                      },
                      'cluster-reconciliation-cycle': {
                        cpu: pgParams.initContainers.clusterReconciliationCycle.requests.cpu,
                        memory: pgParams.initContainers.clusterReconciliationCycle.requests.memory,
                      },
                      'dbops.set-dbops-running': {
                        cpu: pgParams.initContainers.setDbopsRunning.requests.cpu,
                        memory: pgParams.initContainers.setDbopsRunning.requests.memory,
                      },
                    },
                  },
                  containers: {
                    'backup.create-backup': {
                      cpu: pgParams.sideCars.createBackup.limits.cpu,
                      memory: pgParams.sideCars.createBackup.limits.memory,
                    },
                    'cluster-controller': {
                      cpu: pgParams.sideCars.clusterController.limits.cpu,
                      memory: pgParams.sideCars.clusterController.limits.memory,
                    },
                    'dbops.run-dbops': {
                      cpu: pgParams.sideCars.runDbops.limits.cpu,
                      memory: pgParams.sideCars.runDbops.limits.memory,
                    },
                    'dbops.set-dbops-result': {
                      cpu: pgParams.sideCars.setDbopsResult.limits.cpu,
                      memory: pgParams.sideCars.setDbopsResult.limits.memory,
                    },
                    envoy: {
                      cpu: pgParams.sideCars.envoy.limits.cpu,
                      memory: pgParams.sideCars.envoy.limits.memory,
                    },
                    pgbouncer: {
                      cpu: pgParams.sideCars.pgbouncer.limits.cpu,
                      memory: pgParams.sideCars.pgbouncer.limits.memory,
                    },
                    'postgres-util': {
                      cpu: pgParams.sideCars.postgresUtil.limits.cpu,
                      memory: pgParams.sideCars.postgresUtil.limits.memory,
                    },
                    'prometheus-postgres-exporter': {
                      cpu: pgParams.sideCars.prometheusPostgresExporter.limits.cpu,
                      memory: pgParams.sideCars.prometheusPostgresExporter.limits.memory,
                    },
                  },
                  initContainers: {
                    'pgbouncer-auth-file': {
                      cpu: pgParams.initContainers.pgbouncerAuthFile.limits.cpu,
                      memory: pgParams.initContainers.pgbouncerAuthFile.limits.memory,
                    },
                    'relocate-binaries': {
                      cpu: pgParams.initContainers.relocateBinaries.limits.cpu,
                      memory: pgParams.initContainers.relocateBinaries.limits.memory,
                    },
                    'setup-scripts': {
                      cpu: pgParams.initContainers.setupScripts.limits.cpu,
                      memory: pgParams.initContainers.setupScripts.limits.memory,
                    },
                    'setup-arbitrary-user': {
                      cpu: pgParams.initContainers.setupArbitraryUser.limits.cpu,
                      memory: pgParams.initContainers.setupArbitraryUser.limits.memory,
                    },
                    'cluster-reconciliation-cycle': {
                      cpu: pgParams.initContainers.clusterReconciliationCycle.limits.cpu,
                      memory: pgParams.initContainers.clusterReconciliationCycle.limits.memory,
                    },
                    'dbops.set-dbops-running': {
                      cpu: pgParams.initContainers.setDbopsRunning.limits.cpu,
                      memory: pgParams.initContainers.setDbopsRunning.limits.memory,
                    },
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.profileConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'profile'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.metadata.name'),

    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.manifest.spec.cpu', std.mapWithKey(function(key, x) x.size.cpu, pgPlans)),
    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.manifest.spec.memory', std.mapWithKey(function(key, x) x.size.memory, pgPlans)),
    comp.FromCompositeFieldPath('spec.parameters.size.memory', 'spec.forProvider.manifest.spec.memory'),
    comp.FromCompositeFieldPath('spec.parameters.size.cpu', 'spec.forProvider.manifest.spec.cpu'),
    comp.FromCompositeFieldPath('spec.parameters.size.requests.memory', 'spec.forProvider.manifest.spec.requests.memory'),
    comp.FromCompositeFieldPath('spec.parameters.size.requests.cpu', 'spec.forProvider.manifest.spec.requests.cpu'),
  ],
};

local sgPostgresConfig = {
  name: 'pg-conf',
  base: comp.KubeObject('stackgres.io/v1', 'SGPostgresConfig') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {},
                spec: {
                  postgresVersion: '',
                  'postgresql.conf': {},
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.pgconfigConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'pgconf'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.metadata.name'),

    comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgresVersion'),
    comp.FromCompositeFieldPath('spec.parameters.service.pgSettings', 'spec.forProvider.manifest.spec[postgresql.conf]'),
  ],
};

local sgCluster = {
  name: 'cluster',
  base: comp.KubeObject('stackgres.io/v1', 'SGCluster') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {},
                spec: {
                  instances: 1,
                  sgInstanceProfile: '',
                  configurations: {
                    sgPostgresConfig: '',
                    backups:
                      [
                        {
                          sgObjectStorage: '',
                          retention: 6,
                        },
                      ],
                  },
                  postgres: {
                    version: '',
                    ssl: {
                      enabled: true,
                      certificateSecretKeySelector: {
                        name: certificateSecretName,
                        key: 'tls.crt',
                      },
                      privateKeySecretKeySelector: {
                        name: certificateSecretName,
                        key: 'tls.key',
                      },
                    },
                  },
                  pods: {
                    persistentVolume: {
                      size: '',
                    },
                    resources: {
                      enableClusterLimitsRequirements: true,
                    },
                  },
                  nonProductionOptions: {
                    enableSetPatroniCpuRequests: true,
                    enableSetPatroniMemoryRequests: true,
                    enableSetClusterCpuRequests: true,
                    enableSetClusterMemoryRequests: true,

                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.pgclusterConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'cluster'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.metadata.name'),

    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan',
                                                'spec.forProvider.manifest.spec.pods.persistentVolume.size',
                                                std.mapWithKey(function(key, x) x.size.disk, pgPlans)),
    comp.FromCompositeFieldPath('spec.parameters.size.disk', 'spec.forProvider.manifest.spec.pods.persistentVolume.size'),

    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan',
                                                'spec.forProvider.manifest.spec.pods.scheduling.nodeSelector',
                                                std.mapWithKey(function(key, x)
                                                                 std.get(std.get(x, 'scheduling', default={}), 'nodeSelector', default={}),
                                                               pgPlans)),
    comp.FromCompositeFieldPath('spec.parameters.scheduling.nodeSelector', 'spec.forProvider.manifest.spec.pods.scheduling.nodeSelector'),

    comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgres.version'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.spec.sgInstanceProfile'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.spec.configurations.sgPostgresConfig'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.spec.configurations.backups[0].sgObjectStorage', 'sgbackup'),

    comp.FromCompositeFieldPath('spec.parameters.backup.retention', 'spec.forProvider.manifest.spec.configurations.backups[0].retention'),
  ],
};

local xobjectBucket = {
  name: 'pg-bucket',
  base: {
    apiVersion: 'appcat.vshn.io/v1',
    kind: 'XObjectBucket',
    metadata: {},
    spec: {
      parameters: {
        bucketName: '',
        region: pgParams.bucket_region,
      },
      writeConnectionSecretToRef: {
        namespace: params.crossplaneNamespace,
        name: '',
      },
    },
  },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.objectBackupConfigConditions'),
    comp.FromCompositeFieldPath('metadata.name', 'metadata.name'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.parameters.bucketName'),

    // comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.writeConnectionSecretToRef.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.writeConnectionSecretToRef.name', 'pgbucket'),
  ],
};

local sgObjectStorage = {
  name: 'sg-backup',
  base: comp.KubeObject('stackgres.io/v1beta1', 'SGObjectStorage') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {
                  name: '',
                  namespace: '',
                },
                spec: {
                  type: 's3Compatible',
                  s3Compatible: {
                    bucket: '',
                    enablePathStyleAddressing: true,
                    region: pgParams.bucket_region,
                    endpoint: pgParams.bucket_endpoint,
                    awsCredentials: {
                      secretKeySelectors: {
                        accessKeyId: {
                          name: '',
                          key: 'AWS_ACCESS_KEY_ID',
                        },
                        secretAccessKey: {
                          name: '',
                          key: 'AWS_SECRET_ACCESS_KEY',
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.objectBucketConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'object-storage'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'sgbackup'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.spec.s3Compatible.bucket'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.accessKeyId.name', 'pgbucket'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.secretAccessKey.name', 'pgbucket'),
  ],
};

local copyJob = {
  name: 'copy-job',
  base: comp.KubeObject('batch/v1', 'Job') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata+: {
            namespace: params.services.controlNamespace,
          },
          spec: {
            template: {
              spec: {
                ttlSecondsAfterFinished: 100,
                restartPolicy: 'Never',
                serviceAccountName: 'copyserviceaccount',
                containers: [
                  {
                    name: 'copyjob',
                    image: 'bitnami/kubectl:latest',
                    command: [ 'sh', '-c' ],
                    args: [ importstr 'scripts/copy-pg-backup.sh' ],
                    env: [
                      {
                        name: 'CLAIM_NAMESPACE',
                      },
                      {
                        name: 'CLAIM_NAME',
                      },
                      {
                        name: 'BACKUP_NAME',
                      },
                      {
                        name: 'TARGET_NAMESPACE',
                      },
                    ],
                  },
                ],
              },
            },
          },
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'copyjob'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'copyjob'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[0].value'),
    comp.FromCompositeFieldPath('spec.parameters.restore.claimName', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[1].value'),
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[2].value'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[3].value', 'vshn-postgresql'),
  ],
};

local clusterRestoreConfig = {
  name: 'cluster',
  base+: {
    spec+: {
      references+: [
        {
          dependsOn+: {
            apiVersion: 'stackgres.io/v1',
            kind: 'SGBackup',
          },
        },
      ],
    },
  },
  patches+: [
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.forProvider.manifest.spec.initialData.restore.fromBackup.name'),
    comp.FromCompositeFieldPath('spec.parameters.restore.recoveryTimeStamp', 'spec.forProvider.manifest.spec.initialData.restore.fromBackup.pointInTimeRecovery.restoreToTimestamp'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.references[0].dependsOn.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.references[0].dependsOn.name'),
  ],
};


local prometheusRule = prom.GeneratePrometheusNonSLORules(
  'PostgreSQL',
  'patroni',
  [
    {
      name: 'postgresql-connections',
      rules: [
        {
          alert: 'PostgreSQLConnectionsCritical',
          annotations: {
            description: 'The number of connections to the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} have been over 90% of the configured connections for 2 hours.\n  Please reduce the load of this instance.',
            runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLConnectionsCritical',
            summary: 'Connection usage critical',
          },

          expr: std.strReplace(prom.TopPod('sum(pg_stat_activity_count) by (pod, namespace) > 90/100 * sum(pg_settings_max_connections) by (pod, namespace)'), 'vshn-replacemeplease', 'vshn-' + std.asciiLower('PostgreSQL')),
          'for': '120m',
          labels: {
            severity: 'critical',
            syn_team: 'schedar',
          },
        },
      ],
    },
    {
      name: 'postgresql-replication',
      rules: [
        {
          alert: 'PostgreSQLReplicationCritical',
          annotations: {
            description: 'The number of replicas for the instance {{ $labels.cluster_name }} in namespace {{ $labels.namespace }}. Please check pod counts in affected namespace.',
            runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLReplicationCritical',
            summary: 'Replication status check',
          },
          expr: 'pg_replication_slots_active == 0',
          'for': '10m',
          labels: {
            severity: 'critical',
            syn_team: 'schedar',
          },
        },
      ],
    },
    {
      name: 'postgresql-replication-lag',
      rules: [
        {
          alert: 'PostgreSQLReplicationLagCritical',
          annotations: {
            description: 'Replication lag size on namespace {{$labels.exported_namespace}} instance ({{$labels.application_name}}) is currently {{ $value | humanize1024}}B behind the leader.',
            runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLReplicationLagCritical',
            summary: 'Replication lag status check',
          },
          expr: 'pg_replication_status_lag_size > 1e+09',
          'for': '5m',
          labels: {
            severity: 'critical',
            syn_team: 'schedar',
          },
        },
      ],
    },
    {
      name: 'postgresql-replication-count',
      rules: [
        {
          alert: 'PostgreSQLPodReplicasCritical',
          annotations: {
            description: 'Replication is broken in namespace {{$labels.namespace}}, check statefulset ({{$labels.statefulset}}).',
            runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLPodReplicasCritical',
            summary: 'Replication lag status check',
          },
          expr: 'kube_statefulset_status_replicas_available{statefulset=~".+", namespace=~"vshn-postgresql-.+"} != kube_statefulset_replicas{statefulset=~".+",namespace=~"vshn-postgresql-.+"}',
          'for': '5m',
          labels: {
            severity: 'critical',
            syn_team: 'schedar',
          },
        },
      ],
    },
  ]
) + {
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'prometheusrule'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
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

local podMonitor = {
  name: 'podmonitor',
  base: comp.KubeObject('monitoring.coreos.com/v1', 'PodMonitor') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata: {
            name: 'postgresql-podmonitor',
          },
          spec: {
            podMetricsEndpoints: [
              {
                port: 'pgexporter',
                metricRelabelings: [
                  {
                    action: 'keep',
                    sourceLabels: [
                      '__name__',
                    ],
                    regex: '(' + std.join('|', keepMetrics) + ')',
                  },
                ],
              },
            ],
            selector: {
              matchLabels: {
                app: 'StackGresCluster',
              },
            },
          },
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'podmonitor'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.spec.selector.matchLabels[stackgres.io/cluster-name]'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.spec.namespaceSelector.matchNames[0]', 'vshn-postgresql'),
  ],
};

local composition(restore=false) =

  local metadata = if restore then common.vshnMetaVshnDBaas('PostgreSQLRestore', 'standalone', 'false', pgPlans) else common.vshnMetaVshnDBaas('PostgreSQL', 'standalone', 'true', pgPlans);
  local compositionName = if restore then 'vshnpostgresrestore.vshn.appcat.vshn.io' else 'vshnpostgres.vshn.appcat.vshn.io';
  local copyJobFunction(restore) = if restore then [ copyJob ] else [];

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', compositionName) +
  common.SyncOptions +
  metadata +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'patch-and-transform',
            functionRef: {
              name: 'function-patch-and-transform',
            },
            input: {
              apiVersion: 'pt.fn.crossplane.io/v1beta1',
              kind: 'Resources',
              resources: [
                           localca,
                           certificate,
                         ] +
                         copyJobFunction(restore) +
                         [
                           sgInstanceProfile,
                           sgPostgresConfig,
                           sgCluster +
                           if restore then clusterRestoreConfig else {},
                           xobjectBucket,
                           sgObjectStorage,
                           podMonitor,
                         ],
            },
          },
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
                      sideCars: std.toString(pgParams.sideCars),
                      controlNamespace: params.services.controlNamespace,
                      ownerKind: xrd.spec.names.kind,
                      ownerGroup: xrd.spec.group,
                      ownerVersion: xrd.spec.versions[0].name,
                      bucketRegion: pgParams.bucket_region,
                      isOpenshift: std.toString(isOpenshift),
                      sliNamespace: params.slos.namespace,
                    } + std.get(pgParams, 'additionalInputs', default={}, inc_hidden=true)
                    + common.EmailAlerting(params.services.vshn.emailAlerting)
                    + if pgParams.proxyFunction then {
                      proxyEndpoint: pgParams.grpcEndpoint,
                    } else {},
            },
          },
        ],
    },
  };

local defaultComp = composition();
local restoreComp = composition(true);

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

if params.services.vshn.enabled && pgParams.enabled then
  assert std.length(pgParams.bucket_region) != 0 : 'appcat.services.vshn.postgres.bucket_region is empty';
  assert std.length(pgParams.bucket_endpoint) != 0 : 'appcat.services.vshn.postgres.bucket_endpoint is empty';
  {
    '20_xrd_vshn_postgres': xrd,
    '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
    '20_role_vshn_postgresrestore': [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
    '20_plans_vshn_postgresql': plansCM,
    '21_composition_vshn_postgres': defaultComp,
    '21_composition_vshn_postgresrestore': restoreComp,
    '22_prom_rule_sla_postgres': promRulePostgresSLA,
    [if isOpenshift then '21_openshift_template_postgresql_vshn']: osTemplate,
    [if isOpenshift then '10_stackgres_openshift_operator_ns']: stackgresOperatorNs,
    [if isOpenshift then '11_stackgres_openshift_operator']: stackgresOperator,
    [if isOpenshift then '12_stackgres_openshift_operator_netpol']: stackgresNetworkPolicy,
    [if params.slos.enabled && params.services.vshn.enabled && params.services.vshn.postgres.enabled then 'sli_exporter/90_slo_vshn_postgresql']: slos.Get('vshn-postgresql'),
    [if params.slos.enabled && params.services.vshn.enabled && params.services.vshn.postgres.enabled then 'sli_exporter/90_slo_vshn_postgresql_ha']: slos.Get('vshn-postgresql-ha'),
  } else {}
