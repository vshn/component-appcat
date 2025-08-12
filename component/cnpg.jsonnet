local vars = import 'config/vars.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();

local params = inv.parameters.appcat.cnpg;

local namespace =
  if params.monitoring.enabled && std.member(inv.applications, 'prometheus') then
    if params.monitoring.instance != null then
      prometheus.RegisterNamespace(kube.Namespace(params.namespace), params.monitoring.instance)
    else
      prometheus.RegisterNamespace(kube.Namespace(params.namespace))
  else
    kube.Namespace(params.namespace)
;

local name = 'cnpg';
local labels = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'commodore',
};

{
  '00_namespace': namespace {
    metadata+: {
      labels+: params.namespaceLabels,
      annotations+: params.namespaceAnnotations,
    },
  },
}
