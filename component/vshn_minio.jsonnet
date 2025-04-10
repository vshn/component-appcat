local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local common = import 'common.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local minioParams = params.services.vshn.minio;
local opsgenieRules = import 'vshn_alerting.jsonnet';
local prom = import 'prometheus.libsonnet';
local comp = import 'lib/appcat-compositions.libsonnet';


local vars = import 'config/vars.jsonnet';

local instances = [
  kube._Object('vshn.appcat.vshn.io/v1', 'VSHNMinio', instance.name) +
  {
    metadata+: {
      namespace: instance.namespace,
      annotations+: common.ArgoCDAnnotations(),
    },
    spec+: instance.spec,
  } + common.SyncOptions + {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-options': 'Prune=false,SkipDryRunOnMissingResource=true',
      },
    },
  }
  for instance in minioParams.instances
];

local prometheusRule = prom.GeneratePrometheusNonSLORules('minio', 'minio', []) + {
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'prometheusrule'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-minio'),
  ],
};

if params.services.vshn.enabled && minioParams.enabled && std.length(instances) != 0 && vars.isSingleOrControlPlaneCluster then {
  '22_minio_instances': instances,
  '22_minio_prometheus_rule': prometheusRule,
  [if params.slos.alertsEnabled then 'sli_exporter/90_VSHNMinio_Opsgenie']: opsgenieRules.GenGenericAlertingRule('VSHNMinio'),

} else {}
