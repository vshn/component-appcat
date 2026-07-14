local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local common = import 'common.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local minioParams = params.services.vshn.minio;
local vshnAlerting = import 'vshn_alerting_slos.libsonnet';
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

if params.services.vshn.enabled && minioParams.enabled && std.length(instances) != 0 && vars.isSingleOrControlPlaneCluster then {
  '22_minio_instances': instances,
  [if params.slos.alertsEnabled then 'sli_exporter/90_VSHNMinio_Opsgenie']: vshnAlerting.GenGenericAlertingRule('VSHNMinio'),

} else {}
