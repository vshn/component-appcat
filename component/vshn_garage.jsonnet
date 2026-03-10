local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local common = import 'common.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local garageParams = params.services.generic.objectstorage.compositions.garage;
local opsgenieRules = import 'vshn_alerting.jsonnet';
local vars = import 'config/vars.jsonnet';

local instances = [
  kube._Object('vshn.appcat.vshn.io/v1', 'VSHNGarage', instance.name) +
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
  for instance in garageParams.instances
];

if params.services.vshn.enabled && garageParams.enabled && std.length(instances) != 0 then {
  '22_garage_instances': instances,
  [if params.slos.alertsEnabled then 'sli_exporter/90_VSHNGarage_Opsgenie']: opsgenieRules.GenGenericAlertingRule('VSHNGarage'),

} else {}
