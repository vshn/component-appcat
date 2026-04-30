local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.appcat;

local synLabels = {
  syn: 'true',
  syn_component: 'appcat',
  syn_team: 'schedar',
};

local isGaragePrometheusRule(obj) =
  std.type(obj) == 'object'
  && std.get(obj, 'apiVersion', '') == 'monitoring.coreos.com/v1'
  && std.get(obj, 'kind', '') == 'PrometheusRule'
  && std.get(std.get(obj, 'metadata', {}), 'name', '') == 'appcat-garage-operator-garage';

local fixup(obj) =
  if isGaragePrometheusRule(obj) then
    obj {
      metadata+: {
        labels+: synLabels,
      },
      spec+: {
        groups: [
          g {
            rules: [
              r { labels+: synLabels }
              for r in g.rules
            ],
          }
          for g in std.get(std.get(obj, 'spec', {}), 'groups', [])
        ],
      },
    }
  else
    obj;

if params.garageOperator.enabled then
  com.fixupDir(std.extVar('output_path'), fixup)
else
  {}
