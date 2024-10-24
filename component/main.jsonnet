local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local slos = import 'slos.libsonnet';


local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.vshn.postgres;

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


local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';
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
    annotations+: params.namespaceAnnotations,
  },
};

local tenant = {
  // We hardcode the cluster tenant on appuio managed
  [if params.appuioManaged then 'replace']: std.strReplace(|||
    "tenant_id",
    "$1",
    "",
    ""
  |||, '$1', params.billing.tenantID),
  [if params.appuioManaged then 'label']: '',

  // We use the organization label on appuio cloud
  [if !params.appuioManaged then 'replace']: |||
    "tenant_id",
    "$1",
    "label_appuio_io_organization",
    "(.*)"
  |||,
  [if !params.appuioManaged then 'label']: 'label_appuio_io_organization=~".+",',
};

local promQueryTemplate = importstr 'promql/appcat.promql';
local promQueryWithLabel = std.strReplace(promQueryTemplate, '{{ORGLABEL}}', tenant.label);
local promQuery = std.strReplace(promQueryWithLabel, '{{TENANT_REPLACE}}', tenant.replace);

local legacyBillingRule = std.prune(kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'appcat-billing') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'appcat-billing-rules',
        rules: [
          {
            expr: promQuery,
            record: 'appcat:billing',
          },
        ],
      },
    ],
  },
});

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

{
  '10_clusterrole_view': xrdBrowseRole,
  [if isOpenshift then '10_clusterrole_finalizer']: finalizerRole,
  '10_clusterrole_services_read': readServices,
  '10_appcat_namespace': ns,
  '10_appcat_legacy_billing_recording_rule': legacyBillingRule,
  '10_appcat_backup_monitoring': backupPrometheusRule,
  '10_appcat_ha_monitoring': haPrometheusRule,
  [if params.services.vshn.enabled && params.services.emailAlerting.enabled then '10_mailgun_secret']: emailSecret,
  [if params.billing.enableMockOrgInfo then '10_mock_org_info']: mockOrgInfo,
}
