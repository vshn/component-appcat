local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local objStoParams = params.services.generic.objectstorage;

local xrd = xrds.XRDFromCRD(
  'xobjectbuckets.appcat.vshn.io',
  xrds.LoadCRD('appcat.vshn.io_objectbuckets.yaml', params.images.appcat.tag),
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

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'cloudscale.objectbuckets.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaObjectStorage('cloudscale.ch') +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: compParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'cloudscalebucket-func',
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
                providerConfig: 'cloudscale',
                serviceName: 'cloudscalebucket',
                providerSecretNamespace: compParams.providerSecretNamespace,
              } + if compParams.proxyFunction then {
                proxyEndpoint: compParams.grpcEndpoint,
              } else {},
            },
          },
        ],
    },
  };


local compositionExoscale =
  local compParams = objStoParams.compositions.exoscale;

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscale.objectbuckets.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaObjectStorage('Exoscale') +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: compParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'exoscalebucket-func',
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
                providerConfig: 'exoscale',
                serviceName: 'exoscalebucket',
                providerSecretNamespace: compParams.providerSecretNamespace,
              } + if compParams.proxyFunction then {
                proxyEndpoint: compParams.grpcEndpoint,
              } else {},
            },
          },
        ],
    },
  };

local minioComp(name) =
  local compParams = objStoParams.compositions.minio;

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', name + '.objectbuckets.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaObjectStorage('Minio-' + name) +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: compParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'miniobucket-func',
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
                providerConfig: name,
                serviceName: 'miniobucket',
              } + if compParams.proxyFunction then {
                proxyEndpoint: compParams.grpcEndpoint,
              } else {},
            },
          },
        ],
    },
  };

local compositionMinio =
  local provider = params.providers.minio;
  [
    minioComp(config.name)
    for config in provider.additionalProviderConfigs
  ] + [
    minioComp(configRef)
    for configRef in provider.providerConfigRefs
  ] + [
    // Automagically add the defined instances as well
    minioComp(instance.name)
    for instance in params.services.vshn.minio.instances
  ];


if objStoParams.enabled then {
  '20_xrd_objectstorage': xrd,
  '20_rbac_objectstorage': xrds.CompositeClusterRoles(xrd),
  [if objStoParams.compositions.cloudscale.enabled then '21_composition_objectstorage_cloudscale']: compositionCloudscale,
  [if objStoParams.compositions.exoscale.enabled then '21_composition_objectstorage_exoscale']: compositionExoscale,
  [if objStoParams.compositions.minio.enabled then '21_composition_objectstorage_minio']: compositionMinio,
} else {}
