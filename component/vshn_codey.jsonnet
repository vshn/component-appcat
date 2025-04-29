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
local codeyParams = params.services.vshn.codey;
local appuioManaged = inv.parameters.appcat.appuioManaged;

local serviceNameLabelKey = 'appcat.vshn.io/servicename';
local serviceNamespaceLabelKey = 'appcat.vshn.io/claim-namespace';
local serviceCLaimNameLabelKey = 'appcat.vshn.io/claim-name';
local serviceName = 'codey';

local connectionSecretKeys = [
  'CODEY_USERNAME',
  'CODEY_PASSWORD',
  'CODEY_URL',
];

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';

local securityContext = if isOpenshift then false else true;

local codeyPlans = common.FilterDisabledParams(codeyParams.plans);

local xrd = xrds.XRDFromCRD(
  'xcodeyinstances.codey.io',
  xrds.LoadCRD('codey.io_codeyinstances.yaml', params.images.appcat.tag),
  defaultComposition='codey.io',
  connectionSecretKeys=connectionSecretKeys,
);

local composition =
  local vshnforgejo = {
    apiVersion: 'vshn.appcat.vshn.io/v1',
    kind: 'XVSHNForgejo',
    metadata: {
      name: 'vshnforgejo',
    },
    spec: {
      parameters: {
        service: {
          majorVersion: '11.0.0',
          fqdn: [ 'myforgejo.127.0.0.1.nip.io' ],
        },
        size: {
          plan: 'mini',
        },
        security: {
          deletionProtection: false,
        },
      },
    },
  };


  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'codey.io') +
  common.SyncOptions +
  common.vshnMetaVshnDBaas('codey', 'standalone', 'true', codeyPlans) +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: codeyParams.secretNamespace,
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
                {
                  name: 'vshnforgejo',
                  base: vshnforgejo,
                  connectionDetails: [
                    {
                      name: 'CODEY_PASSWORD',
                      type: 'FromConnectionSecretKey',
                      fromConnectionSecretKey: 'FORGEJO_PASSWORD',
                    },
                    {
                      name: 'CODEY_URL',
                      type: 'FromConnectionSecretKey',
                      fromConnectionSecretKey: 'FORGEJO_URL',
                    },
                    {
                      name: 'CODEY_USERNAME',
                      type: 'FromConnectionSecretKey',
                      fromConnectionSecretKey: 'FORGEJO_USERNAME',
                    },
                  ],
                  patches: [
                    comp.FromCompositeFieldPath('metadata.labels["crossplane.io/composite"]', 'metadata.name'),
                    comp.FromCompositeFieldPath('spec.parameters.service.adminEmail', 'spec.parameters.service.adminEmail'),
                    comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.parameters.service.majorVersion'),
                    comp.FromCompositeFieldPathWithTransform('metadata.labels["crossplane.io/claim-name"]', 'spec.parameters.service.fqdn[0]', '', '.app.codey.ch'),
                    comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.parameters.size.plan'),
                  ],
                },
              ],
            },
          },
          // {
          //   step: 'codey-func',
          //   functionRef: {
          //     name: 'function-appcat',
          //   },
          //   input: kube.ConfigMap('xfn-config') + {
          //     metadata: {
          //       labels: {
          //         name: 'xfn-config',
          //       },
          //       name: 'xfn-config',
          //     },
          //     data: {
          //       serviceName: serviceName,
          //       serviceID: common.VSHNServiceID(serviceName),
          //     },
          //   },
          // },
        ],
    },
  };

local plansCM = kube.ConfigMap('codeyplans') + {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    plans: std.toString(codeyPlans),
  },
};

if params.services.vshn.enabled && codeyParams.enabled && vars.isSingleOrControlPlaneCluster then {
  '20_xrd_vshn_codey': xrd,
  '20_rbac_vshn_codey': xrds.CompositeClusterRoles(xrd),
  '21_composition_vshn_codey': composition,
} else {}
