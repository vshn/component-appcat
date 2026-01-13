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

local securityContext = if vars.isOpenshift then false else true;

local codeyPlans = common.FilterDisabledParams(codeyParams.plans);

local xrd = xrds.XRDFromCRD(
  'xcodeyinstances.codey.io',
  xrds.LoadCRD('codey.io_codeyinstances.yaml', params.images.appcat.tag),
  defaultComposition='codey.io',
  connectionSecretKeys=connectionSecretKeys,
) + xrds.WithServiceID(serviceName);

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
          majorVersion: '13.0.4',
          fqdn: [ 'myforgejo.127.0.0.1.nip.io' ],
          forgejoSettings: {
            config: {
              mailer: {
                ENABLED: 'true',
                PROTOCOL: 'smtp+starttls',
                SMTP_ADDR: 'smtp.eu.mailgun.org',
                SMTP_PORT: '587',
                FROM: 'noreply@app.codey.ch',
                USER: params.services.vshn.codey.additionalInputs.smtpUsername,
                PASSWD: params.services.vshn.codey.additionalInputs.smtpPassword,
              },
            },
          },
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

  // Unrolled codeyPlans usable for PnT map transform
  local codeyPlanMappings = {
    cpu: { [plan]: codeyPlans[plan].size.cpu for plan in std.objectFields(codeyPlans) },
    memory: { [plan]: codeyPlans[plan].size.memory for plan in std.objectFields(codeyPlans) },
    disk: { [plan]: codeyPlans[plan].size.disk for plan in std.objectFields(codeyPlans) },
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
                    comp.FromCompositeFieldPathWithConvert('spec.parameters.service.disableRegistration', 'spec.parameters.service.forgejoSettings.config.service."DISABLE_REGISTRATION"', 'string'),
                    comp.FromCompositeFieldPathWithTransform('metadata.labels["crossplane.io/claim-name"]', 'spec.parameters.service.fqdn[0]', '', '.app.codey.ch'),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.parameters.size.cpu', codeyPlanMappings.cpu),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.parameters.size.requests.cpu', codeyPlanMappings.cpu),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.parameters.size.memory', codeyPlanMappings.memory),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.parameters.size.requests.memory', codeyPlanMappings.memory),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.parameters.size.disk', codeyPlanMappings.disk),
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
