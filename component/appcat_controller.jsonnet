local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local xrds = import 'xrds.libsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';
local params = inv.parameters.appcat;
local controllersParams = params.controller;

local image = params.images.appcat;
local loadManifest(manifest) = std.parseJson(kap.yaml_load(inv.parameters._base_directory + '/dependencies/appcat/manifests/' + image.tag + '/config/controller/' + manifest));

// Load the BillingService CRD for the new billing controller
local billingServiceCRD = xrds.LoadCRD('vshn.appcat.vshn.io_billingservices.yaml', image.tag);

local serviceAccount = loadManifest('service-account.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
};

local roleLeaderElection = loadManifest('role-leader-election.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
};

local roleBindingLeaderElection = loadManifest('role-binding-leader-election.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
  subjects: [
    super.subjects[0] {
      namespace: controllersParams.namespace,
    },
  ],
};

local clusterRole = loadManifest('cluster-role.yaml');

local clusterRoleBinding = loadManifest('cluster-role-binding.yaml') {
  subjects: [
    super.subjects[0] {
      namespace: controllersParams.namespace,
    },
  ],
};

local mergedArgs = controllersParams.extraArgs + [
  '--quotas=' + std.toString(controllersParams.quotasEnabled),
  '--billing=' + std.toString(controllersParams.billingEnabled),
  '--crossplane-metrics=' + std.toString(controllersParams.monitoringEnabled),
];

local mergedEnv = com.envList(controllersParams.extraEnv) + std.prune([
  {
    name: 'PLANS_NAMESPACE',
    value: params.namespace,
  },
  if controllersParams.controlPlaneKubeconfig != '' then {
    name: 'CONTROL_PLANE_KUBECONFIG',
    value: '/config/config',
  } else null,
] + if controllersParams.billingEnabled then [
  {
    name: 'ODOO_BASE_URL',
    value: controllersParams.billing.odooBaseURL,
  },
  {
    name: 'ODOO_DB',
    value: controllersParams.billing.odooDb,
  },
  {
    name: 'ODOO_CLIENT_ID',
    value: controllersParams.billing.odooClientID,
  },
  {
    name: 'ODOO_CLIENT_SECRET',
    value: controllersParams.billing.odooClientSecret,
  },
  {
    name: 'ODOO_TOKEN_URL',
    value: controllersParams.billing.odooTokenURL,
  },
  {
    name: 'BILLING_MAX_EVENTS_PRODUCT',
    value: std.toString(controllersParams.billing.maxEventsPerProduct),
  },
] else [] + if controllersParams.monitoringEnabled then [
  {
    name: 'CROSSPLANE_LABEL_MAPPING',
    value: controllersParams.monitoring.crossplane_label_mapping,
  },
  {
    name: 'CROSSPLANE_EXTRA_RESOURCES',
    value: controllersParams.monitoring.crossplane_extra_resources,
  },
] else []);

local controlKubeConfig = kube.Secret('controlclustercredentials') + {
  metadata+: {
    namespace: controllersParams.namespace,
  },
  stringData+: {
    config: params.clusterManagementSystem.controlPlaneKubeconfig,
  },
};


local controller = loadManifest('deployment.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
    annotations+: {
      'metadata.appcat.vshn.io/enabled-services-hash': std.md5(std.join('-', vars.GetEnabledVSHNServiceNames())),
    },
  },
  spec+: {
    replicas: 2,
    template+: {
      metadata+: {
        annotations+: {
          kubeconfighash: std.md5(params.clusterManagementSystem.controlPlaneKubeconfig),
        },
      },
      spec+: {
        volumes: [
          {
            name: 'webhook-certs',
            secret: {
              secretName: controllersParams.tls.certSecretName,
            },
          },
        ] + if controllersParams.controlPlaneKubeconfig != '' then [
          {
            name: 'kubeconfig',
            secret: {
              secretName: 'controlclustercredentials',
            },
          },
        ] else [],
        containers: [
          if c.name == 'manager' then
            c {
              image: common.GetAppCatImageString(),
              args+: mergedArgs,
              env+: mergedEnv,
              resources: controllersParams.resources,
              volumeMounts+: [
                {
                  name: 'webhook-certs',
                  mountPath: '/etc/webhook/certs',
                },
              ] + if controllersParams.controlPlaneKubeconfig != '' then [
                {
                  name: 'kubeconfig',
                  mountPath: '/config',
                },
              ] else [],
            }
          else
            c
          for c in super.containers
        ],
      },
    },
  },
};

local service = loadManifest('service.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
};

local servicemonitor = loadManifest('servicemonitor.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
};

local prometheusrule = std.prune(kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'appcat-crossplane-resources') {
  metadata+: {
    namespace: controllersParams.namespace,
    labels: {
      'app.kubernetes.io/name': 'appcat',
      'app.kubernetes.io/managed-by': 'commodore',
    },
  },
  spec: {
    groups: [
      {
        name: 'crossplane-resources.rules',
        rules: [
          {
            alert: 'CrossplaneResourceUnsynced',
            expr: 'max by (api_version, kind, name, claim_name, claim_namespace, instance_name, status_synced, status_ready) (crossplane_resource_info{status_synced!="ReconcileSuccess"}) == 1',
            'for': '20m',
            labels: {
              severity: 'warning',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
            },
            annotations: {
              summary: 'Crossplane resource {{ $labels.kind }} is not synced',
              description: 'Crossplane resource {{ $labels.name }} ({{ $labels.kind }}) in namespace {{ $labels.claim_namespace }} has status_synced={{ $labels.status_synced }} for more than 20 minutes',
            },
          },
          {
            alert: 'CrossplaneResourceNotReady',
            expr: 'max by (api_version, kind, name, claim_name, claim_namespace, instance_name, status_synced, status_ready) (crossplane_resource_info{status_ready!="Available"}) == 1',
            'for': '15m',
            labels: {
              severity: 'warning',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
            },
            annotations: {
              summary: 'Crossplane resource {{ $labels.kind }} is not ready',
              description: 'Crossplane resource {{ $labels.name }} ({{ $labels.kind }}) in namespace {{ $labels.claim_namespace }} has status_ready={{ $labels.status_ready }} for more than 15 minutes',
            },
          },
        ],
      },
    ],
  },
});

local webhookService = loadManifest('webhook-service.yaml') {
  metadata+: {
    name: 'webhook-service',
    namespace: controllersParams.namespace,
  },
};

local webhookIssuer = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Issuer',
  metadata: {
    name: 'webhook-server-issuer',
    namespace: params.namespace,
  },
  spec: {
    selfSigned: {},
  },
};

local webhookCertificate = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Certificate',
  metadata: {
    name: 'webhook-certificate',
    namespace: params.namespace,
  },
  spec: {
    dnsNames: [ webhookService.metadata.name + '.' + params.namespace + '.svc' ],
    duration: '87600h0m0s',
    issuerRef: {
      group: 'cert-manager.io',
      kind: 'Issuer',
      name: webhookIssuer.metadata.name,
    },
    privateKey: {
      algorithm: 'RSA',
      encoding: 'PKCS1',
      size: 4096,
    },
    renewBefore: '2400h0m0s',
    secretName: controllersParams.tls.certSecretName,
    subject: {
      organizations: [ 'vshn-appcat' ],
    },
    usages: [
      'server auth',
      'client auth',
    ],
  },
};

local clientConfig = {
  clientConfig+: {
    service+: {
      namespace: controllersParams.namespace,
    },
  },
};

local selector = {
  matchExpressions: [
    {
      key: 'appcat.vshn.io/ownerkind',
      operator: 'Exists',
    },
  ],
};

local additionalUnmanagedProtection(group, version, resource) = {
  admissionReviewVersions: [
    'v1',
  ],
  clientConfig: {
    service: {
      name: 'webhook-service',
      namespace: controllersParams.namespace,
      path: '/unmanaged-deletion-protection',
    },
  },
  namespaceSelector: selector,
  failurePolicy: 'Fail',
  name: resource + '.vshn.appcat.vshn.io',
  rules: [
    {
      apiGroups: [
        group,
      ],
      apiVersions: [
        version,
      ],
      operations: [
        'DELETE',
      ],
      resources: [
        resource,
      ],
    },
  ],
  sideEffects: 'None',
};

local webhook = loadManifest('webhooks.yaml') {
  metadata+: {
    name: 'appcat-validation',
    annotations+: {
      'cert-manager.io/inject-ca-from': params.namespace + '/' + webhookCertificate.metadata.name,
    },
  },
  webhooks: [
    if w.name == 'pvc.vshn.appcat.vshn.io' then w { namespaceSelector: selector } + clientConfig else
      if w.name == 'namespace.vshn.appcat.vshn.io' then w { objectSelector: selector } + clientConfig else
        if w.name == 'xobjectbuckets.vshn.appcat.vshn.io' then w { objectSelector: selector } + clientConfig
        else w + clientConfig
    for w in super.webhooks
  ] + [
    additionalUnmanagedProtection(h.group, h.version, h.resource)
    for h in controllersParams.additionalUnmanagedProtection
  ],
};

if controllersParams.enabled then {
  'controllers/appcat/10_role_leader_election': roleLeaderElection,
  'controllers/appcat/10_cluster_role': clusterRole,
  'controllers/appcat/10_role_binding_leader_election': roleBindingLeaderElection,
  'controllers/appcat/10_cluster_role_binding': clusterRoleBinding,
  'controllers/appcat/10_webhooks': webhook,
  'controllers/appcat/10_webhook_service': webhookService,
  'controllers/appcat/10_webhook_issuer': webhookIssuer,
  'controllers/appcat/10_webhook_certificate': webhookCertificate,
  'controllers/appcat/10_billingservice_crd': billingServiceCRD,
  'controllers/appcat/20_service_account': serviceAccount,
  'controllers/appcat/30_deployment': controller,
  [if controllersParams.controlPlaneKubeconfig != '' then 'controllers/appcat/10_controlplane_credentials']: controlKubeConfig,
  [if controllersParams.monitoringEnabled then 'controllers/appcat/40_service']: service,
  [if controllersParams.monitoringEnabled then 'controllers/appcat/40_servicemonitor']: servicemonitor,
  [if controllersParams.monitoringEnabled then 'controllers/appcat/40_prometheusrule']: prometheusrule,
} else {}
