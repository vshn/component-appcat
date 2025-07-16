local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.appcat.billing;
local paramsCloud = inv.parameters.appcat.billing.cloud;
local common = import 'common.libsonnet';
local kube = import 'lib/kube.libjsonnet';
local com = import 'lib/commodore.libjsonnet';
local collectorImage = '%(registry)s/%(repository)s:%(tag)s' % inv.parameters.appcat.images.collector;
local component_name = 'billing-collector-cloudservices';
local appuioManaged = inv.parameters.appcat.appuioManaged;

local labels = {
  'app.kubernetes.io/name': component_name,
  'app.kubernetes.io/managed-by': 'commodore',
  'app.kubernetes.io/component': component_name,
};

local secret(key, suf) = [
  if paramsCloud.secrets[key][s] != null then
    kube.Secret(s + '-' + key + if suf != '' then '-' + suf else '') {
      metadata+: {
        namespace: params.namespace,
      },
      stringData+: {
        ODOO_OAUTH_CLIENT_ID: params.odoo.oauth.clientID,
        ODOO_OAUTH_CLIENT_SECRET: params.odoo.oauth.clientSecret,
        CONTROL_API_URL: params.controlAPI.url,
        CONTROL_API_TOKEN: params.controlAPI.token,
      },
    } + com.makeMergeable(paramsCloud.secrets[key][s])
  for s in std.objectFields(paramsCloud.secrets[key])
];

local exoDbaasClusterRole = kube.ClusterRole('appcat:cloudcollector:exoscale:dbaas') + {
  rules: [
    {
      apiGroups: [ '*' ],
      resources: [ 'namespaces' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ 'exoscale.crossplane.io' ],
      resources: [
        'postgresqls',
        'mysqls',
        'redis',
        'opensearches',
        'kafkas',
      ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
  ],
};

local exoObjectStorageClusterRole = kube.ClusterRole('appcat:cloudcollector:exoscale:objectstorage') + {
  rules: [
    {
      apiGroups: [ '*' ],
      resources: [ 'namespaces' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ 'exoscale.crossplane.io' ],
      resources: [
        'buckets',
      ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
  ],
};

local cloudscaleClusterRole = kube.ClusterRole('appcat:cloudcollector:cloudscale') + {
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'namespaces' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ 'cloudscale.crossplane.io' ],
      resources: [
        'buckets',
      ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
  ],
};

local serviceAccount(name, clusterRole) = {
  local sa = kube.ServiceAccount(name) + {
    metadata+: {
      namespace: params.namespace,
    },
  },
  local rb = kube.ClusterRoleBinding(name) {
    roleRef_: clusterRole,
    subjects_: [ sa ],
  },
  sa: sa,
  rb: rb,
};

local deployment(name, args, config) =
  kube.Deployment(name) {
    metadata+: {
      labels+: labels { 'automated-billing': 'true' },
      namespace: params.namespace,
    },
    spec+: {
      template+: {
        spec+: {
          serviceAccount: name,
          containers_:: {
            exporter: kube.Container('exporter') {
              image: collectorImage,
              args: args,
              // add resource limits
              // during my local tests it consumes arround 50% of requests{} values
              resources: {
                limits: {
                  cpu: '250m',
                  memory: '256Mi',
                },
                requests: {
                  cpu: '100m',
                  memory: '128Mi',
                },
              },
              envFrom: [
                {
                  configMapRef: {
                    name: config,
                  },
                },
                {
                  secretRef: {
                    name: 'credentials-' + name,
                  },
                },
              ],
              ports: [
                {
                  containerPort: 2112,
                  protocol: 'TCP',
                },
              ],
            },
          },
        },
      },
    },
  };


local service = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    labels: labels { 'automated-billing': 'true' },
    name: 'automated-billing',
    namespace: params.namespace,
  },
  spec: {
    ports: [
      {
        name: 'metrics',
        port: 2112,
        protocol: 'TCP',
        targetPort: 2112,
      },
    ],
    selector: {
      'automated-billing': 'true',
    },
  },
};

local config(name, extraConfig) = kube.ConfigMap(name) {
  metadata: {
    name: name,
    namespace: params.namespace,
  },
  data: {
    ODOO_URL: std.toString(params.odoo.url),
    ODOO_OAUTH_TOKEN_URL: std.toString(params.odoo.oauth.url),
    CLUSTER_ID: std.toString(params.clusterID),
    APPUIO_MANAGED_SALES_ORDER: if appuioManaged then std.toString(params.salesOrder) else '',
    CLOUD_ZONE: params.cloudZone,
    UOM: std.toString(paramsCloud.uom),
  },
} + extraConfig;

local alertRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    labels: labels { 'automated-billing': 'true' },
    name: 'cloudservices-billing',
    namespace: params.namespace,
  },
  spec: {
    groups+: [
      {
        name: 'odoo_http_failures',
        rules: [
          {
            alert: 'HighOdooHTTPFailureRate',
            expr: |||
              billing_cloud_collector_http_requests_odoo_failed_total != 0
            |||,
            'for': '1m',
            labels: {
              severity: 'critical',
              syn_team: 'schedar',
            },
            annotations: {
              summary: 'High rate of Odoo HTTP failures detected',
              description: 'The rate of failed Odoo HTTP requests (`billing_cloud_collector_http_requests_odoo_failed_total`) has increased significantly in the last minute.',
            },
          },
          {
            alert: 'HighProviderHTTPFailureRate',
            expr: |||
              billing_cloud_collector_http_requests_provider_failed_total != 0
            |||,
            'for': '1m',
            labels: {
              severity: 'critical',
              syn_team: 'schedar',
            },
            annotations: {
              summary: "High rate of Automated-billing collector's providers HTTP failures detected",
              description: 'The rate of failed Odoo HTTP requests (`billing_cloud_collector_http_requests_provider_failed_total`) has increased significantly in the last minute.',
            },
          },
        ],
      },
    ],
  },
};


local serviceMonitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    labels: labels { 'automated-billing': 'true' },
    name: 'cloudservices-servicemonitor',
    namespace: params.namespace,
  },
  spec: {
    endpoints: [
      {
        port: 'metrics',
      },
    ],
    selector: {
      matchLabels+: { 'automated-billing': 'true' },
    },
  },
};


({
   local odoo = params.odoo,
   assert odoo.oauth != null : 'odoo.oauth must be set.',
   assert odoo.oauth.clientID != null : 'odoo.oauth.clientID must be set.',
   assert odoo.oauth.clientSecret != null : 'odoo.oauth.clientSecret must be set.',
 })
+
(if paramsCloud.exoscale.enabled && paramsCloud.exoscale.dbaas.enabled then {
   local name = 'exoscale-dbaas',
   local secrets = paramsCloud.secrets.exoscale,
   local sa = serviceAccount(name, exoDbaasClusterRole),
   local extraConfig = {
     data+: {
       COLLECT_INTERVAL: std.toString(paramsCloud.exoscale.dbaas.collectIntervalMinutes),
     },
   },
   local cm = config(name + '-env', extraConfig),

   assert secrets != null : 'secrets must be set.',
   assert secrets.credentials != null : 'secrets.credentials must be set.',
   assert secrets.credentials.stringData != null : 'secrets.credentials.stringData must be set.',
   assert secrets.credentials.stringData.EXOSCALE_API_KEY != null : 'secrets.credentials.stringData.EXOSCALE_API_KEY must be set.',
   assert secrets.credentials.stringData.EXOSCALE_API_SECRET != null : 'secrets.credentials.stringData.EXOSCALE_API_SECRET must be set.',

   '10_exoscale_dbaas_secret': std.filter(function(it) it != null, secret('exoscale', 'dbaas')),
   '10_exoscale_dbaas_cluster_role': exoDbaasClusterRole,
   '10_exoscale_dbaas_service_account': sa.sa,
   '10_exoscale_dbaas_role_binding': sa.rb,
   '10_exoscale_dbaas_configmap': cm,
   '10_exoscale_dbaas_exporter': deployment(name, [ 'exoscale', 'dbaas' ], name + '-env'),
 } else {})
+
(if paramsCloud.exoscale.enabled && paramsCloud.exoscale.objectStorage.enabled then {
   local name = 'exoscale-objectstorage',
   local secrets = paramsCloud.secrets.exoscale,
   local sa = serviceAccount(name, exoObjectStorageClusterRole),
   local extraConfig = {
     data+: {
       COLLECT_INTERVAL: std.toString(paramsCloud.exoscale.objectStorage.collectIntervalHours),
       BILLING_HOUR: std.toString(paramsCloud.exoscale.objectStorage.billingHour),
     },
   },
   local cm = config(name + '-env', extraConfig),

   assert secrets != null : 'secrets must be set.',
   assert secrets.credentials != null : 'secrets.credentials must be set.',
   assert secrets.credentials.stringData != null : 'secrets.credentials.stringData must be set.',
   assert secrets.credentials.stringData.EXOSCALE_API_KEY != null : 'secrets.credentials.stringData.EXOSCALE_API_KEY must be set.',
   assert secrets.credentials.stringData.EXOSCALE_API_SECRET != null : 'secrets.credentials.stringData.EXOSCALE_API_SECRET must be set.',

   '10_exoscale_object_storage_secret': std.filter(function(it) it != null, secret('exoscale', 'objectstorage')),
   '10_exoscale_object_storage_cluster_role': exoObjectStorageClusterRole,
   '10_exoscale_object_storage_service_account': sa.sa,
   '10_exoscale_object_storage_rolebinding': sa.rb,
   '10_exoscale_object_storage_configmap': cm,
   '20_exoscale_object_storage_exporter': deployment(name, [ 'exoscale', 'objectstorage' ], name + '-env'),

 } else {})
+
(if paramsCloud.cloudscale.enabled then {
   local name = 'cloudscale',
   local secrets = paramsCloud.secrets.cloudscale,
   local sa = serviceAccount(name, cloudscaleClusterRole),
   local extraConfig = {
     data+: {
       COLLECT_INTERVAL: std.toString(paramsCloud.cloudscale.collectIntervalHours),
       BILLING_HOUR: std.toString(paramsCloud.cloudscale.billingHour),
       DAYS: std.toString(paramsCloud.cloudscale.days),
     },
   },
   local cm = config(name + '-env', extraConfig),

   assert secrets != null : 'secrets must be set.',
   assert secrets.credentials != null : 'secrets.credentials must be set.',
   assert secrets.credentials.stringData != null : 'secrets.credentials.stringData must be set.',
   assert secrets.credentials.stringData.CLOUDSCALE_API_TOKEN != null : 'secrets.credentials.stringData.CLOUDSCALE_API_TOKEN must be set.',

   '10_cloudscale_secrets': std.filter(function(it) it != null, secret(name, '')),
   '10_cloudscale_cluster_role': cloudscaleClusterRole,
   '10_cloudscale_service_account': sa.sa,
   '10_cloudscale_rolebinding': sa.rb,
   '10_cloudscale_configmap': cm,
   '20_cloudscale_exporter': deployment(name, [ 'cloudscale', 'objectstorage' ], name + '-env'),
 } else {})
+
// We only need the alert rule once
(if paramsCloud.cloudscale.enabled || paramsCloud.exoscale.enabled then {
   '30_billing_alerts': alertRule,
   '40_billing_servicemonitor': serviceMonitor,
 } else {})
