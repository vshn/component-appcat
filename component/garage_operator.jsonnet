local vars = import 'config/vars.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.appcat.garageOperator;

local namespace = kube.Namespace(params.namespace);

if params.enabled then
  {
    '00_namespace': namespace,
  } else {}
