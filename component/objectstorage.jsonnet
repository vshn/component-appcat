local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local objStoParams = params.converged.objectstorage;

local xrd = xrds.XRDFromCRD(
  'xobjectbuckets.appcat.vshn.io',
  xrds.LoadCRD('appcat.vshn.io_objectbuckets.yaml'),
  defaultComposition='%s.objectbuckets.appcat.vshn.io' % objStoParams.defaultComposition,
  connectionSecretKeys=[
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_REGION',
    'ENDPOINT',
    'ENDPOINT_URL',
    'BUCKET_NAME',
  ]
);

local compositionCloudscale =
  local compParams = objStoParams.compositions.cloudscale;

  local baseUser = {
    apiVersion: 'cloudscale.crossplane.io/v1',
    kind: 'ObjectsUser',
    metadata: {},
    spec: {
      forProvider: {
        displayName: '',
        tags: {
          namespace: null,
          tenant: null,
        },
      },
      writeConnectionSecretToRef: {
        name: '',
        namespace: compParams.providerSecretNamespace,
      },
      providerConfigRef: {
        name: 'cloudscale',
      },
    },
  };

  local baseBucket = {
    apiVersion: 'cloudscale.crossplane.io/v1',
    kind: 'Bucket',
    metadata: {},
    spec: {
      forProvider: {
        bucketName: '',
        credentialsSecretRef: {
          name: '',
          namespace: compParams.providerSecretNamespace,
        },
        endpointURL: '',
        region: '',
        bucketDeletionPolicy: compParams.bucketDeletionPolicy,
      },
    },
  };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'cloudscale.objectbuckets.appcat.vshn.io') + common.SyncOptions + {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: compParams.secretNamespace,
      patchSets: [
        comp.PatchSet('annotations'),
        comp.PatchSet('labels'),
      ],
      resources: [
        {
          base: baseUser,
          connectionDetails: [
            comp.conn.FromSecretKey('AWS_ACCESS_KEY_ID'),
            comp.conn.FromSecretKey('AWS_SECRET_ACCESS_KEY'),
          ],
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.ToCompositeFieldPath('status.conditions', 'status.accessUserConditions'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),
            {
              type: 'CombineFromComposite',
              toFieldPath: 'spec.forProvider.displayName',
              combine: {
                variables: [
                  {
                    fromFieldPath: 'metadata.labels[crossplane.io/claim-namespace]',
                  },
                  {
                    fromFieldPath: 'metadata.labels[crossplane.io/claim-name]',
                  },
                ],
                strategy: 'string',
                string: {
                  fmt: '%s.%s',
                },
              },
            },
          ],
        },
        {
          base: baseBucket,
          connectionDetails: [
            comp.conn.FromFieldPath('ENDPOINT', 'status.endpoint'),
            comp.conn.FromFieldPath('ENDPOINT_URL', 'status.endpointURL'),
            comp.conn.FromFieldPath('AWS_REGION', 'spec.forProvider.region'),
            comp.conn.FromFieldPath('BUCKET_NAME', 'status.atProvider.bucketName'),
          ],
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.ToCompositeFieldPath('status.conditions', 'status.bucketConditions'),
            comp.FromCompositeFieldPath('spec.parameters.bucketName', 'spec.forProvider.bucketName'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.credentialsSecretRef.name'),
            comp.FromCompositeFieldPath('spec.parameters.region', 'spec.forProvider.region') {
              transforms: [
                {
                  type: 'map',
                  map: {
                    rma: 'rma',
                    lpg: 'lpg',
                  },
                },
              ],
            },
          ],
        },
      ],
    },
  };


local compositionExsoscale =
  local compParams = objStoParams.compositions.exoscale;

  local IAMKeyBase = {
    apiVersion: 'exoscale.crossplane.io/v1',
    kind: 'IAMKey',
    metadata: {},
    spec: {
      forProvider: {
        keyName: '',
        zone: '',
        services: {
          sos: {
            buckets: [
              '',
            ],
          },
        },
      },
      writeConnectionSecretToRef: {
        name: '',
        namespace: compParams.providerSecretNamespace,
      },
      providerConfigRef: {
        name: 'exoscale',
      },
    },
  };
  local bucketBase = {
    apiVersion: 'exoscale.crossplane.io/v1',
    kind: 'Bucket',
    metadata: {},
    spec: {
      forProvider: {
        bucketName: '',
        zone: '',
        bucketDeletionPolicy: compParams.bucketDeletionPolicy,
      },
      providerConfigRef: {
        name: 'exoscale',
      },
    },
  };

  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: compParams.secretNamespace,
      patchSets: [
        comp.PatchSet('annotations'),
        comp.PatchSet('labels'),
      ],
      resources: [
        {
          base: IAMKeyBase,
          connectionDetails: [
            comp.conn.FromSecretKey('AWS_ACCESS_KEY_ID'),
            comp.conn.FromSecretKey('AWS_SECRET_ACCESS_KEY'),
          ],
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.ToCompositeFieldPath('status.conditions', 'status.accessUserConditions'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),
            {
              type: 'CombineFromComposite',
              toFieldPath: 'spec.forProvider.keyName',
              combine: {
                variables: [
                  {
                    fromFieldPath: 'metadata.labels[crossplane.io/claim-namespace]',
                  },
                  {
                    fromFieldPath: 'metadata.labels[crossplane.io/claim-name]',
                  },
                ],
                strategy: 'string',
                string: {
                  fmt: '%s.%s',
                },
              },
            },
            comp.FromCompositeFieldPath('spec.parameters.region', 'spec.forProvider.zone'),
            comp.FromCompositeFieldPath('spec.parameters.bucketName', 'spec.forProvider.services.sos.buckets[0]'),
          ],
        },
        {
          base: bucketBase,
          connectionDetails: [
            comp.conn.FromFieldPath('ENDPOINT', 'status.endpoint'),
            comp.conn.FromFieldPath('ENDPOINT_URL', 'status.endpointURL'),
            comp.conn.FromFieldPath('AWS_REGION', 'spec.forProvider.zone'),
            comp.conn.FromFieldPath('BUCKET_NAME', 'status.atProvider.bucketName'),
          ],
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.ToCompositeFieldPath('status.conditions', 'status.bucketConditions'),
            comp.FromCompositeFieldPath('spec.parameters.bucketName', 'spec.forProvider.bucketName'),
            comp.FromCompositeFieldPath('spec.parameters.region', 'spec.forProvider.zone'),
          ],
        },
      ],
    },
  };

if objStoParams.enabled then {
  '20_xrd_objectstorage': xrd,
  '20_rbac_objectstorage': xrds.CompositeClusterRoles(xrd),
  [if objStoParams.compositions.cloudscale.enabled then '21_composition_objectstorage_cloudscale']: compositionCloudscale,
  [if objStoParams.compositions.exoscale.enabled then '21_composition_objectstorage_exoscale']: compositionExsoscale,
} else {}
