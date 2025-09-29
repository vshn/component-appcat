local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local slos = import 'slos.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.vshn.postgres;
local appuioManaged = inv.parameters.appcat.appuioManaged;

assert vars.isCMSValid : 'controlPlaneCluster and serviceCluster in clusterManagementSystem cannot be both false';

local xrdBrowseRole = kube.ClusterRole('appcat:browse') + {
  metadata+: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-view': 'true',
      'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
      'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    },
  },
  rules+: [
    {
      apiGroups: [ 'apiextensions.crossplane.io' ],
      resources: [
        'compositions',
        'compositionrevisions',
        'compositeresourcedefinitions',
      ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};


local finalizerRole = kube.ClusterRole('crossplane:appcat:finalizer') {
  metadata+: {
    labels: {
      'rbac.crossplane.io/aggregate-to-crossplane': 'true',
    },
  },
  rules+: [
    {
      apiGroups: [
        'appcat.vshn.io',
        'vshn.appcat.vshn.io',
        'exoscale.appcat.vshn.io',
      ],
      resources: [
        '*/finalizers',
      ],
      verbs: [ '*' ],
    },
  ],

};

local readServices = kube.ClusterRole('appcat:services:read') + {
  rules+: [
    {
      apiGroups: [ '' ],
      resources: [ 'pods', 'pods/log', 'pods/status', 'events', 'services', 'namespaces' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'statefulsets' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'pods/portforward' ],
      verbs: [ 'get', 'list', 'create' ],
    },
    {
      apiGroups: [ '', 'project.openshift.io' ],
      resources: [ 'projects' ],
      verbs: [ 'get' ],
    },
  ],
};

// adding namespace for syn-appcat
local ns = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      'openshift.io/cluster-monitoring': 'true',
    } + params.namespaceLabels,
    annotations+:
      if !appuioManaged then {
        'resourcequota.appuio.io/organization-objects.jobs': '300',
      } + params.namespaceAnnotations
      else params.namespaceAnnotations,
  },
};

local mockOrgInfo = kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'mock-org-info') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'mock-org-info',
        rules: [
          {
            expr: '1',
            record: 'appuio_control_organization_info',
            labels: {
              organization: 'awesomekorp',
              sales_order: 'ST10120',
            },
          },
          {
            expr: '1',
            record: 'appuio_control_organization_info',
            labels: {
              organization: 'notvshn',
              sales_order: 'invalid',
            },
          },
        ],
      },
    ],
  },
};

local emailSecret = kube.Secret(params.services.emailAlerting.secretName) {
  metadata+: {
    namespace: params.services.emailAlerting.secretNamespace,
  },
  stringData: {
    password: params.services.emailAlerting.smtpPassword,
  },
};

local filterName(name) = if name == 'postgres' then 'postgresql' else name;
local jobRegex = std.foldl(function(prev, current) (if prev == '' then filterName(current.name) else prev + '|' + filterName(current.name)), common.FilterServiceByBoolean('enabled'), '');

local backupPrometheusRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'appcat-backup',
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'appcat-backup',
        rules: [
          {
            alert: 'AppCatBackupJobError',
            annotations: {
              description: 'The backup job {{ $labels.job_name }} in namespace {{ $labels.namespace }} has failed.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/how-tos/appcat/AppCatBackupJobError.html',
              summary: 'AppCat service backup failed.',
            },
            expr: 'kube_job_failed{job_name=~".*backup.*", namespace=~"vshn-(' + jobRegex + ')-.*"} > 0',
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

local haPrometheusRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'appcat-ha',
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'appcat-ha',
        rules: [
          {
            alert: 'AppCatHighAvailableDeploymentWarning',
            annotations: {
              description: 'The deployment {{ $labels.deployment }} in namespace {{ $labels.namespace }} has less replicas than expected.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/how-tos/appcat/vshn/AppCatHighAvailableDeploymentWarning.html',
              summary: 'AppCat service instance has unavailable pods.',
            },
            expr: 'kube_deployment_status_replicas{namespace=~"vshn-(' + jobRegex + ')-.*"} > 1 AND kube_deployment_status_replicas{namespace=~"vshn-(' + jobRegex + ')-.*"} - kube_deployment_status_replicas_ready{namespace=~"vshn-(' + jobRegex + ')-.*"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              syn_team: 'schedar',
            },
          },
          {
            alert: 'AppCatHighAvailableStatefulsetWarning',
            annotations: {
              description: 'The statefulset {{ $labels.statefulset }} in namespace {{ $labels.namespace }} has less replicas than expected.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/how-tos/appcat/vshn/AppCatHighAvailableStatefulsetWarning.html',
              summary: 'AppCat service instance has unavailable pods.',
            },
            expr: 'kube_statefulset_status_replicas{namespace=~"vshn-(' + jobRegex + ')-.*"} > 1 AND kube_statefulset_status_replicas{namespace=~"vshn-(' + jobRegex + ')-.*"} - kube_statefulset_status_replicas_ready{namespace=~"vshn-(' + jobRegex + ')-.*"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              syn_team: 'schedar',
            },
          },
        ],
      },
    ],
  },
};

local controlKubeConfig = kube.Secret('controlclustercredentials') + {
  metadata+: {
    namespace: params.slos.sli_exporter.kustomize_input.namespace,
  },
  stringData+: {
    config: params.slos.sli_exporter.controlPlaneKubeconfig,
  },
};

local serviceClusterKubeconfigs =
  std.foldl(
    function(agg, kubeConf)
      agg + kube.Secret('kubeconfig-' + kubeConf.name) + {
        metadata+: {
          namespace: params.crossplane.namespace,
        },
        stringData+: {
          kubeconfig: kubeConf.config,
        },
      },
    params.clusterManagementSystem.serviceClusterKubeconfigs,
    {}
  );

local serviceClusterSA = kube.ServiceAccount('appcat-service-cluster') + {
  metadata+: {
    namespace: params.namespace,
  },
};

local serviceClusterRoleBindingCrossplane = kube.ClusterRoleBinding('appcat:service:cluster:crossplane') {
  roleRef: {
    kind: 'ClusterRole',
    name: 'crossplane-view',
    apiGroup: 'rbac.authorization.k8s.io',
  },
  subjects_: [ serviceClusterSA ],
};

// The SLI probier needs additional RBAC to read the connection detail secrets
local serviceClusterRole = kube.ClusterRole('appcat:service:cluster:custom') + {
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local serviceClusterRoleBindingCustom = kube.ClusterRoleBinding('appcat:service:cluster:custom') {
  roleRef_: serviceClusterRole,
  subjects_: [ serviceClusterSA ],
};

local serviceClusterSATokenSecret = kube.Secret('appcat-service-cluster') + {
  metadata+: {
    namespace: params.namespace,
    annotations: {
      'kubernetes.io/service-account.name': serviceClusterSA.metadata.name,
    },
  },
  type: 'kubernetes.io/service-account-token',
};

local controlPlaneSATokenSecret = kube.Secret('appcat-control-plane') + {
  metadata+: {
    namespace: params.namespace,
    annotations: {
      'kubernetes.io/service-account.name': common.ControlPlaneSa.metadata.name,
    },
  },
  type: 'kubernetes.io/service-account-token',
};

// The API server needs additional RBAC to read the k8up snapshots
local controlPlaneRole = kube.ClusterRole('appcat:controlplane:custom') + {
  rules: [
    {
      apiGroups: [ 'k8up.io' ],
      resources: [ 'snapshots' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local controlPlaneRoleBindingCustom = kube.ClusterRoleBinding('appcat:controlplane:custom') {
  roleRef_: controlPlaneRole,
  subjects_: [ common.ControlPlaneSa ],
};

local servalaServiceAccount = kube.ServiceAccount('servala-portal') + {
  metadata+: {
    namespace: params.namespace,
  },
};

local servalaClusterRole = kube.ClusterRole('servala:portal:custom') + {
  rules: [
    {
      apiGroups: [ 'apiextensions.k8s.io' ],
      resources: [ 'customresourcedefinitions' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'namespaces' ],
      verbs: [ 'create', 'get', 'list', 'watch', 'update', 'patch', 'delete' ],
    },
    {
      apiGroups: [ 'vshn.appcat.vshn.io' ],
      resources: [ '*' ],
      verbs: [ 'create', 'get', 'list', 'watch', 'update', 'patch', 'delete' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get' ],
    },
  ],
};

local servalaClusterBinding = kube.ClusterRoleBinding('servala:portal') {
  roleRef_: servalaClusterRole,
  subjects_: [ servalaServiceAccount ],
};

local servalaSATokenSecret = kube.Secret('servala-portal') + {
  metadata+: {
    namespace: params.namespace,
    annotations: {
      'kubernetes.io/service-account.name': servalaServiceAccount.metadata.name,
    },
  },
  type: 'kubernetes.io/service-account-token',
};

{
  '10_clusterrole_view': xrdBrowseRole,
  [if vars.isOpenshift then '10_clusterrole_finalizer']: finalizerRole,
  '10_clusterrole_services_read': readServices,
  '10_appcat_namespace': ns,
  '10_appcat_backup_monitoring': backupPrometheusRule,
  '10_appcat_ha_monitoring': haPrometheusRule,
  [if params.services.vshn.enabled && params.services.emailAlerting.enabled then '10_mailgun_secret']: emailSecret,
  [if params.billing.enableMockOrgInfo then '10_mock_org_info']: mockOrgInfo,
  [if params.slos.enabled && vars.isServiceCluster && params.slos.sli_exporter.controlPlaneKubeconfig != '' then 'sli_exporter/10_service_cluster_kubeconfig']: controlKubeConfig,
  // This is ugly, but otherwise the post-processing will fail for
  // golden tests where things get dynamically enabeld or disabled, so we
  // can't use an enabled filter in the post processing...
  'controllers/sts-resizer/.keep': '',
  [if std.length(params.clusterManagementSystem.serviceClusterKubeconfigs) != 0 then '10_service_cluster_kubeconfigs']: serviceClusterKubeconfigs,
} + (if vars.isSingleOrServiceCluster then {
       '11_control_plane_sa': common.ControlPlaneSa,
       '11_control_plane_sa_token_secret': controlPlaneSATokenSecret,
       '11_control_plane_custom_role': controlPlaneRole,
       '11_control_plan_role_binding_custom': controlPlaneRoleBindingCustom,
     } else {})
+ (if vars.isSingleOrControlPlaneCluster then {
     '11_service_cluster_sa': serviceClusterSA,
     '11_service_cluster_sa_token_secret': serviceClusterSATokenSecret,
     '11_service_cluster_sa_custom_role': serviceClusterRole,
     '11_service_cluster_role_binding_crossplane': serviceClusterRoleBindingCrossplane,
     '11_service_cluster_role_binding_custom': serviceClusterRoleBindingCustom,
   } else {})
+ if vars.isControlPlane then {
  '12_servala_service_account': servalaServiceAccount,
  '12_servala_cluster_role_binding': servalaClusterBinding,
  '12_servala_sa_token_secret': servalaSATokenSecret,
  '12_servala_cluster_role': servalaClusterRole,
} else {}
