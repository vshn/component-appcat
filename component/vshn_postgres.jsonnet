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

assert std.length(pgParams.bucket_region) != 0 : 'bucket_region variable must be set, it should be one of: https://docs.appuio.cloud/appcat/references/clouds.html ';
assert std.length(pgParams.bucket_endpoint) != 0 : "bucket_endpoint variable must be set and correspond to valid s3 bucket endpoint in either cloudscale or exoscale, for cloudscale pattern is: objects.$region.cloudscale.ch, for exoscale pattern is: sos-$region}.exo.io. This variable can't start with https://, just host part.";

local defaultDB = 'postgres';
local defaultUser = 'postgres';
local defaultPort = '5432';


local connectionSecretKeys = [
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
);


local composition =
  local namespace = comp.KubeObject('v1', 'Namespace') +
                    {
                      spec+: {
                        forProvider+: {
                          manifest+: {
                            metadata: {
                              name: '',
                            },
                          },
                        },
                      },
                    };

  local sgInstanceProfile = comp.KubeObject('stackgres.io/v1', 'SGInstanceProfile') +
                            {
                              spec+: {
                                forProvider+: {
                                  manifest+: {
                                    metadata: {
                                      name: '',
                                      namespace: '',
                                    },
                                    spec: {
                                      cpu: '',
                                      memory: '',
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
                            };

  local sgPostgresConfig = comp.KubeObject('stackgres.io/v1', 'SGPostgresConfig') +
                           {
                             spec+: {
                               forProvider+: {
                                 manifest+: {
                                   metadata: {
                                     name: '',
                                     namespace: '',
                                   },
                                   spec: {
                                     postgresVersion: '',
                                     'postgresql.conf': {},
                                   },
                                 },
                               },
                             },
                           };

  local sgCluster = comp.KubeObject('stackgres.io/v1', 'SGCluster') +
                    {
                      spec+: {
                        forProvider+: {
                          manifest+: {
                            metadata: {
                              name: '',
                              namespace: '',
                            },
                            spec: {
                              instances: 1,
                              sgInstanceProfile: '',
                              configurations: {
                                sgPostgresConfig: '',
                                backups:
                                  [
                                    {
                                      sgObjectStorage: '',
                                      cronSchedule: '0 22 * * *',
                                      retention: 6,
                                    },
                                  ],
                              },
                              postgres: {
                                version: '',
                              },
                              pods: {
                                persistentVolume: {
                                  size: '',
                                },
                              },
                            },
                          },
                        },
                      },
                    };

  local secret = comp.KubeObject('v1', 'Secret') +
                 {
                   spec+: {
                     forProvider+: {
                       manifest+: {
                         metadata: {
                           name: '',
                           namespace: '',
                         },
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
                     ],
                   },
                 };

  local networkPolicy = comp.KubeObject('networking.k8s.io/v1', 'NetworkPolicy') +
                        {
                          spec+: {
                            forProvider+: {
                              manifest+: {
                                metadata: {
                                  name: '',
                                  namespace: '',
                                },
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
                                      ],
                                    },
                                  ],
                                },
                              },
                            },
                          },
                        };
  local objectBucket = comp.KubeObject('appcat.vshn.io/v1', 'ObjectBucket') +
                       {
                         spec+: {
                           forProvider+: {
                             manifest+: {
                               metadata: {
                                 name: '',
                                 namespace: '',
                               },
                               spec: {
                                 parameters: {
                                   bucketName: '',
                                   region: pgParams.bucket_region,
                                 },
                                 compositionRef: {
                                   name: 'cloudscale.objectbuckets.appcat.vshn.io',
                                 },
                                 writeConnectionSecretToRef: {
                                   namespace: pgParams.secretNamespace,
                                   name: '',
                                 },
                               },
                             },
                           },
                         },
                       };

  local sgObjectStorage = comp.KubeObject('stackgres.io/v1beta1', 'SGObjectStorage') +
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
                          };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'vshnpostgres.vshn.appcat.vshn.io') + common.SyncOptions +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      patchSets: [
        comp.PatchSet('annotations'),
        comp.PatchSet('labels'),
      ],
      resources: [
        {
          base: namespace,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'vshn-postgresql'),
          ],
        },
        {
          base: sgInstanceProfile,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'profile'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

            comp.FromCompositeFieldPath('spec.parameters.size.memory', 'spec.forProvider.manifest.spec.memory'),
            comp.FromCompositeFieldPath('spec.parameters.size.cpu', 'spec.forProvider.manifest.spec.cpu'),
          ],
        },
        {
          base: sgPostgresConfig,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'pgconf'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgresVersion'),
            comp.FromCompositeFieldPath('spec.parameters.service.pgSettings', 'spec.forProvider.manifest.spec[postgresql.conf]'),
          ],
        },
        {
          base: sgCluster,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'cluster'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

            comp.FromCompositeFieldPath('spec.parameters.size.disk', 'spec.forProvider.manifest.spec.pods.persistentVolume.size'),
            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgres.version'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.sgInstanceProfile'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.sgPostgresConfig'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.backups[0].sgObjectStorage', 'sgbackup'),

            comp.FromCompositeFieldPath('spec.parameters.backup.schedule', 'spec.forProvider.manifest.spec.configurations.backups[0].cronSchedule'),
            comp.FromCompositeFieldPath('spec.parameters.backup.retention', 'spec.forProvider.manifest.spec.configurations.backups[0].retention'),
            // add backup configuration
          ],
        },
        {
          base: secret,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'connection'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.metadata.namespace'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.forProvider.manifest.metadata.name', 'connection'),

            comp.CombineCompositeFromTwoFieldPaths('metadata.labels[crossplane.io/composite]', 'metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.stringData.POSTGRESQL_HOST', '%s.vshn-postgresql-%s.svc.cluster.local'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.name'),
          ],
        },
        // s3 bucket creation for backup purposes
        {
          base: objectBucket,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 's3-bucket'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 's3-bucket'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.parameters.bucketName', 's3-bucket'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.spec.writeConnectionSecretToRef.namespace'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.writeConnectionSecretToRef.name', 's3-bucket'),
          ],
        },
        // s3 bucket creation for backup purposes
        {
          base: sgObjectStorage,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'object-storage'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'sgbackup'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.bucket', 's3-bucket'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.spec.writeConnectionSecretToRef.namespace'),
            //pgParams.bucket_endpoint
            comp.FromCompositeFieldPathWithTransform('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.endpoint', 'https://s3-bucket-', '.' + pgParams.bucket_endpoint),

            //
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.accessKeyId.name', 's3-bucket'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.secretAccessKey.name', 's3-bucket'),
          ],
        },
      ] + if pgParams.enableNetworkPolicy == true then [
        {
          base: networkPolicy,
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'network-policy'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'allow-from-claim-namespace'),

            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.ingress[0].from[0].namespaceSelector.matchLabels[kubernetes.io/metadata.name]'),
          ],
        },
      ] else [],
    },
  };


if params.services.vshn.enabled && pgParams.enabled then {
  '20_xrd_vshn_postgres': xrd,
  '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
  '21_composition_vshn_postgres': composition,
} else {}
