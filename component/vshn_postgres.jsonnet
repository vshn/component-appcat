local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.vshn.postgres;

local defaultDB = 'postgres';
local defaultUser = 'postgres';
local defaultPort = '5432';

local certificateSecretName = 'tls-certificate';

local serviceNameLabelKey = 'appcat.vshn.io/servicename';
local serviceNamespaceLabelKey = 'appcat.vshn.io/claim-namespace';

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
];

local xrd = xrds.XRDFromCRD(
  'xvshnpostgresqls.vshn.appcat.vshn.io',
  xrds.LoadCRD('vshn.appcat.vshn.io_vshnpostgresqls.yaml'),
  defaultComposition='vshnpostgres.vshn.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
) + xrds.WithPlanDefaults(pgPlans, pgParams.defaultPlan);


local controlNamespace = kube.Namespace(pgParams.controlNamespace);

local restoreServiceAccount = kube.ServiceAccount('copyserviceaccount') + {
  metadata+: {
    namespace: pgParams.controlNamespace,
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

local namespace = comp.KubeObject('v1', 'Namespace') +
                  {
                    spec+: {
                      forProvider+: {
                        manifest+: {
                          metadata: {
                            name: '',
                            labels: {
                              [serviceNameLabelKey]: 'postgresql-standalone',
                              [serviceNamespaceLabelKey]: '',
                              'appuio.io/no-rbac-creation': 'true',
                              'appuio.io/organization': 'vshn',
                            },
                          },
                        },
                      },
                    },
                  };

local namespaceObserve = {
  name: 'ns-observer',
  base: namespace {
    spec+: {
      managementPolicy: 'Observe',
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'ns-observer'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.metadata.name'),
    comp.ToCompositeFieldPath('status.atProvider.manifest.metadata.labels[appuio.io/organization]', 'metadata.labels[appuio.io/organization]'),
  ],
};

local namespaceConditions = {
  name: 'namespace-conditions',
  base: namespace,
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.namespaceConditions'),
    comp.ToCompositeFieldPath('metadata.name', 'status.instanceNamespace'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.metadata.labels[%s]' % serviceNamespaceLabelKey),
    comp.FromCompositeFieldPath('metadata.labels[appuio.io/organization]', 'spec.forProvider.manifest.metadata.labels[appuio.io/organization]'),
  ],
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
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'localca'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
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
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'certificate'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.issuerRef.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
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
                  },
                  containers: {
                    'backup.create-backup': {
                      cpu: '250m',
                      memory: '256Mi',
                    },
                    'cluster-controller': {
                      cpu: '32m',
                      memory: '188Mi',
                    },
                    envoy: {
                      cpu: '32m',
                      memory: '64Mi',
                    },
                    pgbouncer: {
                      cpu: '16m',
                      memory: '32Mi',
                    },
                    'postgres-util': {
                      cpu: '10m',
                      memory: '4Mi',
                    },
                    'prometheus-postgres-exporter': {
                      cpu: '10m',
                      memory: '32Mi',
                    },
                  },
                  initContainers: {
                    'pgbouncer-auth-file': {
                      cpu: '100m',
                      memory: '100Mi',
                    },
                    'relocate-binaries': {
                      cpu: '100m',
                      memory: '100Mi',
                    },
                    'setup-scripts': {
                      cpu: '100m',
                      memory: '100Mi',
                    },
                    'setup-arbitrary-user': {
                      cpu: '100m',
                      memory: '100Mi',
                    },
                    'cluster-reconciliation-cycle': {
                      cpu: '100m',
                      memory: '100Mi',
                    },
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.profileConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'profile'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

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
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'pgconf'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

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
                          cronSchedule: '',
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
                  },
                  nonProductionOptions: {
                    enableSetPatroniCpuRequests: true,
                    enableSetPatroniMemoryRequests: true,
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.pgclusterConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'cluster'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

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
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.sgInstanceProfile'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.sgPostgresConfig'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.backups[0].sgObjectStorage', 'sgbackup'),

    comp.FromCompositeFieldPath('spec.parameters.backup.schedule', 'spec.forProvider.manifest.spec.configurations.backups[0].cronSchedule'),
    comp.FromCompositeFieldPath('spec.parameters.backup.retention', 'spec.forProvider.manifest.spec.configurations.backups[0].retention'),
  ],
};

local secret = {
  name: 'connection',
  base: comp.KubeObject('v1', 'Secret') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {},
                stringData: {
                  POSTGRESQL_USER: defaultUser,
                  POSTGRESQL_PORT: defaultPort,
                  POSTGRESQL_DB: defaultDB,
                  POSTGRESQL_HOST: '',
                },
              },
            },
            references: [
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  namespace: '',
                  name: '',
                  fieldPath: 'data.superuser-password',
                },
                toFieldPath: 'data.POSTGRESQL_PASSWORD',
              },
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  name: certificateSecretName,
                  namespace: '',
                  fieldPath: 'data[ca.crt]',
                },
                toFieldPath: 'data[ca.crt]',
              },
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  name: certificateSecretName,
                  namespace: '',
                  fieldPath: 'data[tls.crt]',
                },
                toFieldPath: 'data[tls.crt]',
              },
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  name: certificateSecretName,
                  namespace: '',
                  fieldPath: 'data[tls.key]',
                },
                toFieldPath: 'data[tls.key]',
              },
            ],
            // Make crossplane aware of the connection secret we are creating in this object
            writeConnectionSecretToRef: {
              name: '',
              namespace: '',
            },
          },
        },
  connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.secretConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'connection'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.forProvider.manifest.metadata.name', 'connection'),

    comp.CombineCompositeFromTwoFieldPaths('metadata.labels[crossplane.io/composite]', 'metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.stringData.POSTGRESQL_HOST', '%s.vshn-postgresql-%s.svc.cluster.local'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.writeConnectionSecretToRef.name', 'connection'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[1].patchesFrom.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[2].patchesFrom.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[3].patchesFrom.namespace', 'vshn-postgresql'),
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
        namespace: '',
        name: '',
      },
    },
  },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.objectBackupConfigConditions'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.parameters.bucketName'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name', 'pgbucket'),
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
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'object-storage'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'sgbackup'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.bucket'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.spec.writeConnectionSecretToRef.namespace'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.accessKeyId.name', 'pgbucket'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.secretAccessKey.name', 'pgbucket'),
  ],
};

local networkPolicy = {
  name: 'network-policy',
  base: comp.KubeObject('networking.k8s.io/v1', 'NetworkPolicy') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {},
                spec: {
                  policyTypes: [
                    'Ingress',
                  ],
                  podSelector: {},
                  ingress: [
                    {
                      from: [
                        {
                          namespaceSelector: {
                            matchLabels: {
                              'kubernetes.io/metadata.name': '',
                            },
                          },
                        },
                        {
                          namespaceSelector: {
                            matchLabels: {
                              'kubernetes.io/metadata.name': params.slos.namespace,
                            },
                          },
                        },
                      ],
                    },
                  ],
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.networkPolicyConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'network-policy'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'allow-from-claim-namespace'),

    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.ingress[0].from[0].namespaceSelector.matchLabels[kubernetes.io/metadata.name]'),
  ],
};

local copyJob = {
  name: 'copy-job',
  base: comp.KubeObject('batch/v1', 'Job') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata+: {
            namespace: pgParams.controlNamespace,
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
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'copyjob'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'copyjob'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[0].value'),
    comp.FromCompositeFieldPath('spec.parameters.restore.claimName', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[1].value'),
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[2].value'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[3].value', 'vshn-postgresql'),
  ],
};

local clusterRestoreConfig = {
  name: 'cluster-restore',
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
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[0].dependsOn.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.references[0].dependsOn.name'),
  ],
};

local maintenanceServiceAccount = {
  name: 'maintenance-serviceaccount',
  base: comp.KubeObject('v1', 'ServiceAccount') + {
    spec+: {
      forProvider+: {
        manifest+: kube.ServiceAccount('maintenanceserviceaccount'),
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'maintenanceserviceaccount'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local maintenanceRole = {
  name: 'maintenance-role',
  base: comp.KubeObject('rbac.authorization.k8s.io/v1', 'Role') + {
    spec+: {
      forProvider+: {
        manifest+: kube.Role('crossplane:appcat:job:postgres:maintenance') + {
          rules: [
            {
              apiGroups: [ 'stackgres.io' ],
              resources: [ 'sgdbops' ],
              verbs: [
                'delete',
                'create',
              ],
            },
          ],
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'maintenancerole'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local maintenanceRoleBinding = {
  name: 'maintenance-rolebinding',
  base: comp.KubeObject('rbac.authorization.k8s.io/v1', 'RoleBinding') + {
    spec+: {
      forProvider+: {
        manifest+: {
          roleRef: {
            apiGroup: 'rbac.authorization.k8s.io',
            kind: 'Role',
            name: 'crossplane:appcat:job:postgres:maintenance',
          },
          subjects: [
            {
              apiGroup: '',
              kind: 'ServiceAccount',
              name: 'maintenanceserviceaccount',
            },
          ],
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'maintenancerolebinding'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'maintenancerolebinding'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local convertToCron() = [
  // This function produces patches, that will convert dayOdWeek and timeOfDay
  // to a proper cron string. It does that by using maps and regex. As well as
  // environment patches.
  {
    type: 'FromCompositeFieldPath',
    fromFieldPath: 'spec.parameters.maintenance.dayOfWeek',
    toFieldPath: 'metadata.annotations[dayOfWeek]',
    transforms: [
      {
        type: 'map',
        map: {
          monday: '1',
          tuesday: '2',
          wednesday: '3',
          thursday: '4',
          friday: '5',
          saturday: '6',
          sunday: '0',
        },
      },
    ],
  },
  {
    type: 'FromCompositeFieldPath',
    fromFieldPath: 'spec.parameters.maintenance.timeOfDay',
    toFieldPath: 'metadata.annotations[hour]',
    transforms: [
      {
        type: 'string',
        string: {
          type: 'Regexp',
          regexp: {
            match: '(\\d+):(\\d+):.*',
            group: 1,
          },
        },
      },
    ],
  },
  {
    type: 'FromCompositeFieldPath',
    fromFieldPath: 'spec.parameters.maintenance.timeOfDay',
    toFieldPath: 'metadata.annotations[minute]',
    transforms: [
      {
        type: 'string',
        string: {
          type: 'Regexp',
          regexp: {
            match: '(\\d+):(\\d+):.*',
            group: 2,
          },
        },
      },
    ],
  },
  {
    type: 'ToEnvironmentFieldPath',
    fromFieldPath: 'metadata.annotations[minute]',
    toFieldPath: 'maintenance.minute',
  },
  {
    type: 'ToEnvironmentFieldPath',
    fromFieldPath: 'metadata.annotations[hour]',
    toFieldPath: 'maintenance.hour',
  },
  {
    type: 'ToEnvironmentFieldPath',
    fromFieldPath: 'metadata.annotations[dayOfWeek]',
    toFieldPath: 'maintenance.dayOfWeek',
  },
  {
    type: 'CombineFromEnvironment',
    toFieldPath: 'spec.forProvider.manifest.spec.schedule',
    combine: {
      variables: [
        { fromFieldPath: 'maintenance.minute' },
        { fromFieldPath: 'maintenance.hour' },
        { fromFieldPath: 'maintenance.dayOfWeek' },
      ],
      strategy: 'string',
      string: {
        fmt: '%s %s * * %s',
      },
    },
  },
];

local maintenanceJob = {
  name: 'maintenancejob',
  base: comp.KubeObject('batch/v1', 'CronJob') + {
    spec+: {
      forProvider+: {
        manifest+: {
          spec: {
            successfulJobsHistoryLimit: 0,
            jobTemplate: {
              spec: {
                template: {
                  spec: {
                    restartPolicy: 'Never',
                    serviceAccountName: 'maintenanceserviceaccount',
                    containers: [
                      {
                        name: 'maintenancejob',
                        image: 'bitnami/kubectl:latest',
                        command: [ 'sh', '-c' ],
                        args: [ importstr 'scripts/pg-maintenance.sh' ],
                        env: [
                          {
                            name: 'TARGET_NAMESPACE',
                          },
                          {
                            name: 'TARGET_INSTANCE',
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
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'maintenancejob'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'maintenancejob'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.jobTemplate.spec.template.spec.containers[0].env[0].value', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.jobTemplate.spec.template.spec.containers[0].env[1].value'),
  ] + convertToCron(),
};

local prometheusRule = {
  name: 'prometheusrule',
  base: comp.KubeObject('monitoring.coreos.com/v1', 'PrometheusRule') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata: {
            name: 'postgresql-rules',
          },
          spec: {
            groups: [
              {
                name: 'postgresql-storage',
                rules: [
                  {
                    alert: 'PostgreSQLPersistentVolumeFillingUp',
                    annotations: {
                      description: 'The PersistentVolume claimed by {{ $labels.persistentvolumeclaim\n              }} in Namespace {{ $labels.namespace }} is only {{ $value |\n              humanizePercentage }} free.',
                      runbook_url: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepersistentvolumefillingup',
                      summary: 'PersistentVolume is filling up.',
                    },
                    expr: '(\n            kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"}\n              /\n            kubelet_volume_stats_capacity_bytes{job="kubelet", metrics_path="/metrics"}\n          ) < 0.03\n          and\n          kubelet_volume_stats_used_bytes{job="kubelet", metrics_path="/metrics"} > 0\n          unless on(namespace, persistentvolumeclaim)\n          kube_persistentvolumeclaim_access_mode{ access_mode="ReadOnlyMany"} == 1\n          unless on(namespace, persistentvolumeclaim)\n          kube_persistentvolumeclaim_labels{label_excluded_from_alerts="true"} == 1',
                    'for': '1m',
                    labels: {
                      severity: 'critical',
                    },
                  },
                  {
                    alert: 'PostgreSQLPersistentVolumeFillingUp',
                    annotations: {
                      description: 'Based on recent sampling, the PersistentVolume claimed by {{\n              $labels.persistentvolumeclaim }} in Namespace {{ $labels.namespace\n              }} is expected to fill up within four days. Currently {{ $value |\n              humanizePercentage }} is available.',
                      runbook_url: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepersistentvolumefillingup',
                      summary: 'PersistentVolume is filling up.',
                    },
                    expr: '(\n            kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"}\n              /\n            kubelet_volume_stats_capacity_bytes{job="kubelet", metrics_path="/metrics"}\n          ) < 0.15\n          and\n          kubelet_volume_stats_used_bytes{job="kubelet", metrics_path="/metrics"} > 0\n          and\n          predict_linear(kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"}[6h], 4 * 24 * 3600) < 0\n          unless on(namespace, persistentvolumeclaim)\n          kube_persistentvolumeclaim_access_mode{ access_mode="ReadOnlyMany"} == 1\n          unless on(namespace, persistentvolumeclaim)\n          kube_persistentvolumeclaim_labels{label_excluded_from_alerts="true"} == 1',
                    'for': '1h',
                    labels: {
                      severity: 'warning',
                    },
                  },
                ],
              },
              {
                name: 'postgresql-memory',
                rules: [
                  {
                    alert: 'PostgreSQLMemoryCritical',
                    annotations: {
                      description: 'The memory claimed by {{ $labels.pod }} has been over 85% for 2 hours.\n  Please reducde the load of this instance, or increase the memory.',
                      // runbook_url: 'TBD',
                      summary: 'Memory usage critical',
                    },
                    expr: '(container_memory_working_set_bytes{container="patroni"}\n  / on(container,pod)\n  kube_pod_container_resource_limits{resource="memory"} * 100)\n  > 85',
                    'for': '120m',
                    labels: {
                      severity: 'critical',
                    },
                  },
                ],
              },
              {
                name: 'postgresql-connections',
                rules: [
                  {
                    alert: 'PostgreSQLConnectionsCritical',
                    annotations: {
                      description: 'The connections to {{ $labels.pod }} have been over 90% of the configured connections for 2 hours.\n  Please reduce the load of this instance.',
                      // runbook_url: 'TBD',
                      summary: 'Connection usage critical',
                    },
                    expr: 'sum(pg_stat_activity_count) by (pod)\n  > 90/100 * sum(pg_settings_max_connections) by (pod)',
                    'for': '120m',
                    labels: {
                      severity: 'critical',
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'prometheusrule'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

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
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'podmonitor'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.selector.matchLabels[stackgres.io/cluster-name]'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.namespaceSelector.matchNames[0]', 'vshn-postgresql'),
  ],
};

local composition(restore=false) =

  local metadata = if restore then common.VshnMetaVshn('PostgreSQLRestore', 'standalone', 'false') else common.VshnMetaVshn('PostgreSQL', 'standalone');
  local compositionName = if restore then 'vshnpostgresrestore.vshn.appcat.vshn.io' else 'vshnpostgres.vshn.appcat.vshn.io';
  local copyJobFunction(restore) = if restore then [ copyJob ] else [];

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', compositionName) +
  common.SyncOptions +
  metadata +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      functions: [
        {
          name: 'vshn-postgres-func',
          type: 'Container',
          container: {
            image: 'ghcr.io/vshn/vshn-postgres-func:v0.0.1',
            imagePullPolicy: 'IfNotPresent',
          },
        },
      ],
      resources: [
                   namespaceObserve,
                   namespaceConditions,
                   comp.NamespacePermissions('vshn-postgresql'),
                   localca,
                   certificate,
                 ] +
                 copyJobFunction(restore) +
                 [
                   sgInstanceProfile,
                   sgPostgresConfig,
                   sgCluster +
                   if restore then clusterRestoreConfig else {},
                   secret,
                   xobjectBucket,
                   sgObjectStorage,
                   maintenanceServiceAccount,
                   maintenanceRole,
                   maintenanceRoleBinding,
                   maintenanceJob,
                   podMonitor,
                   prometheusRule,
                 ] + if pgParams.enableNetworkPolicy == true then [
        networkPolicy,
      ] else [],
    },
  };

local defaultComp = composition();
local restoreComp = composition(true);

if params.services.vshn.enabled && pgParams.enabled then
  assert std.length(pgParams.bucket_region) != 0 : 'appcat.services.vshn.postgres.bucket_region is empty';
  assert std.length(pgParams.bucket_endpoint) != 0 : 'appcat.services.vshn.postgres.bucket_endpoint is empty';
  {
    '20_xrd_vshn_postgres': xrd,
    '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
    '20_role_vshn_postgresrestore': [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
    '20_namespace_vshn_control': controlNamespace,
    '21_composition_vshn_postgres': defaultComp,
    '21_composition_vshn_postgresrestore': restoreComp,
  } else {}
