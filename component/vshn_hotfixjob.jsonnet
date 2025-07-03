local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;

local hotfixerSA = kube.ServiceAccount('appcat-hotfixer-sa') {
  metadata+: {
    namespace: params.namespace,
  },
};

local escapedComponentVersion = std.strReplace(inv.parameters.components.appcat.version, '.', '-');
local escapedAppCatVersion = std.strReplace(common.GetAppCatImageTag(), '_', '-');

local hotfixerJob = kube.Job('appcat-hotfixer-' + escapedAppCatVersion + '-' + escapedComponentVersion) {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: hotfixerSA.metadata.name,
        containers_:: {
          hotfixer: kube.Container('hotfixer') {
            image: common.GetAppCatImageString(),
            resources: {
              requests: {
                cpu: '10m',
                memory: '200Mi',
              },
              limits: {
                cpu: '100m',
                memory: '300Mi',
              },
            },
            env: [
              {
                name: 'RELEASE_MANAGEMENT_ENABLED',
                value: std.toString(params.deploymentManagementSystem.enabled),
              },
            ],
            args: [
              'hotfixer',
            ],
          },
        },
      },
    },
  },
};

local hotfixClusterRolebinding = kube.ClusterRoleBinding('crossplane:appcat:job:hotfixer:crossplane:edit') + {
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'crossplane-edit',
  },
  subjects_: [ hotfixerSA ],
};

local appcatJobPrometheusRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'appcat-hotfix',
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'appcat-jobs',
        rules: [
          {
            alert: 'AppCatHotfixJobError',
            annotations: {
              description: 'The hotfixjob job {{ $labels.job_name }} in namespace {{ $labels.namespace }} has failed.',
              summary: 'AppCat Hotfix job has failed. Hotfixes might not be rolled out.',
            },
            expr: 'kube_job_failed{job_name="appcat-hotfixer", namespace="' + params.namespace + '"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              syn_team: 'schedar',
              syn: 'true',
              syn_component: 'appcat',
            },
          },
        ],
      },
    ],
  },
};

local currentVersion = inv.parameters.components.appcat.version + '-' + params.images.appcat.tag;

(if vars.isSingleOrControlPlaneCluster && (params.deploymentManagementSystem.hotfix == currentVersion) then {
   'hotfixer/10_job': hotfixerJob,
   'hotfixer/10_sa': hotfixerSA,
   'hotfixer/10_clusterrolebinding': hotfixClusterRolebinding,
 } else {})
+ {
  'hotfixer/10_prometheusrule': appcatJobPrometheusRule,
}
