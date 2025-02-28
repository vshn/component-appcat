local vars = import 'config/vars.jsonnet';
local crossplane = import 'lib/appcat-crossplane.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();

local params = inv.parameters.appcat.crossplane;

local rbacFinalizerRole = kube.ClusterRole('crossplane-rbac-manager:finalizer') {
  rules+: [
    {
      apiGroups: [
        'pkg.crossplane.io',
        'apiextensions.crossplane.io',
      ],
      resources: [
        '*/finalizers',
      ],
      verbs: [ '*' ],
    },
  ],

};
local rbacFinalizerRoleBinding = kube.ClusterRoleBinding('crossplane-rbac-manager:finalizer') {
  roleRef_: rbacFinalizerRole,
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'rbac-manager',
      namespace: params.namespace,
    },
  ],
};

local namespace =
  if params.monitoring.enabled && std.member(inv.applications, 'prometheus') then
    if params.monitoring.instance != null then
      prometheus.RegisterNamespace(kube.Namespace(params.namespace), params.monitoring.instance)
    else
      prometheus.RegisterNamespace(kube.Namespace(params.namespace))
  else
    kube.Namespace(params.namespace)
;

local name = 'crossplane';
local labels = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'commodore',
};
local monitoring =
  [
    kube.Service(name + '-metrics') {
      metadata+: {
        namespace: params.namespace,
        labels+: labels,
      },
      spec+: {
        selector: {
          release: 'crossplane',
        },
        ports: [ {
          name: 'metrics',
          port: 8080,
        } ],
      },
    },
    kube._Object('monitoring.coreos.com/v1', 'ServiceMonitor', name) {
      metadata+: {
        namespace: params.namespace,
        labels+: labels,
      },
      spec: {
        endpoints: [ {
          port: 'metrics',
          path: '/metrics',
        } ],
        selector: {
          matchLabels: labels,
        },
      },
    },
    kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', name) {
      metadata+: {
        namespace: params.namespace,
        labels+: labels {
          role: 'alert-rules',
        } + params.monitoring.prometheus_rule_labels,
      },
      spec: {
        groups: [
          {
            name: 'crossplane.rules',
            rules: [
              {
                alert: 'CrossplaneDown',
                expr: 'up{namespace="' + params.namespace + '", job=~"^crossplane-.+$"} != 1',
                'for': '10m',
                labels: {
                  severity: 'critical',
                  syn: 'true',
                },
                annotations: {
                  summary: 'Crossplane controller is down',
                  description: 'Crossplane pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is down',
                },
              },
            ],
          },
        ],
      },
    },
  ];
if vars.isSingleOrControlPlaneCluster then
  {
    '00_namespace': namespace {
      metadata+: {
        labels+: params.namespaceLabels,
        annotations+: params.namespaceAnnotations,
      },
    },
    '01_rbac_finalizer_clusterrole': rbacFinalizerRole,
    '01_rbac_finalizer_clusterrolebinding': rbacFinalizerRoleBinding,
    [if params.monitoring.enabled then '20_monitoring']: monitoring,
  } else {}
