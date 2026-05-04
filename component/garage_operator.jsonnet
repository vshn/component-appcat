local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'prometheus.libsonnet';
local inv = kap.inventory();

local params = inv.parameters.appcat.garageOperator;

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      'openshift.io/cluster-monitoring': 'true',
      'openshift.io/user-monitoring': 'false',
    },
  },
};

// Scrapes garage pods (port 3903/admin) across all instance namespaces.
// namespaceSelector: any: true is intentional — garage instances live in vshn-garage-*
// namespaces which cannot be enumerated statically. Label selector is tight enough
// to avoid collisions (garage-operator stamps these labels on GarageCluster services).
local garageServiceMonitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    name: 'garage-pods',
    namespace: params.namespace,
    labels: {
      syn: 'true',
      syn_team: 'schedar',
      syn_component: 'appcat',
    },
  },
  spec: {
    namespaceSelector: { any: true },
    selector: {
      matchLabels: {
        'app.kubernetes.io/managed-by': 'garage-operator',
        'app.kubernetes.io/name': 'garage',
      },
    },
    endpoints: [ {
      port: 'admin',
      path: '/metrics',
      interval: '30s',
      relabelings: [ {
        targetLabel: 'job',
        replacement: 'garage',
      } ],
    } ],
  },
};

local garagePrometheusRule =
  prom.GeneratePrometheusNonSLORules('Garage', 'garage', []).base.spec.forProvider.manifest {
    metadata+: {
      namespace: params.namespace,
      labels+: {
        syn: 'true',
        syn_component: 'appcat',
        syn_team: 'schedar',
      },
    },
  };

if params.enabled then {
  '00_namespace': namespace,
  '10_garage_servicemonitor': garageServiceMonitor,
  '20_garage_prometheusrule': garagePrometheusRule,
} else {}
