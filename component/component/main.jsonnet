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

local meteringQueryCloud = importstr 'promql/metering_cloud.promql';
local meteringQueryManagedRaw = importstr 'promql/metering_managed.promql';
local meteringQueryManaged = std.strReplace(meteringQueryManagedRaw, '{{salesOrder}}', params.salesOrder);

local legacyBillingRule = kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'appcat-billing') {
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
};

local meteringRule = kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'appcat-metering') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'appcat-metering-rules',
        rules: [
          {
            expr: if params.appuioManaged then meteringQueryManaged else meteringQueryCloud,
            record: 'appcat:metering',
          },
        ],
      },
    ],
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

local emailSecret = kube.Secret(params.services.vshn.emailAlerting.secretName) {
  metadata+: {
    namespace: params.services.vshn.emailAlerting.secretNamespace,
  },
  stringData: {
    password: params.services.vshn.emailAlerting.smtpPassword,
  },
};

{
  '10_clusterrole_view': xrdBrowseRole,
  [if isOpenshift then '10_clusterrole_finalizer']: finalizerRole,
  '10_clusterrole_services_read': readServices,
  '10_appcat_namespace': ns,
  '10_appcat_legacy_billing_recording_rule': legacyBillingRule,
  [if params.billing.vshn.meteringRules then '10_appcat_metering_recording_rule']: meteringRule,
  [if params.services.vshn.enabled && params.services.vshn.emailAlerting.enabled then '10_mailgun_secret']: emailSecret,
  [if params.billing.enableMockOrgInfo then '10_mock_org_info']: mockOrgInfo,
}
