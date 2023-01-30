local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local crossplane = import 'lib/crossplane.libsonnet';


local inv = kap.inventory();
local params = inv.parameters.appcat;


local addCredentials(config, credentials) = config {
  credentials: std.get(config, 'credentials', default=credentials),
};

local providerSecret(credentials) =
  kube.Secret(credentials.name) {
    metadata+: {
      namespace: credentials.namespace,
    },
    stringData: credentials.data,
  };


local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');
local openshiftControllerConfig =
  (if isOpenshift then {
     podSecurityContext: {},
     securityContext: {},
   }
   else {});


local controllerConfig(name, config) =
  local spec = config + openshiftControllerConfig;
  if spec != {} then
    [
      crossplane.ControllerConfig(name) {
        spec+: spec,
      },
    ]
  else [];

local controllerConfigRef(config) =
  if config != [] then
    {
      controllerConfigRef: {
        name: config[0].metadata.name,
      },
    }
  else {};

{
  [if params.providers.cloudscale.enabled then '10_provider_cloudscale']:
    local provider = params.providers.cloudscale;

    local controllerConf = controllerConfig('cloudscale', provider.controllerConfig);
    [
      crossplane.Provider('cloudscale') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
      crossplane.ProviderConfig('cloudscale') {
        apiVersion: 'cloudscale.crossplane.io/v1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
            apiTokenSecretRef: {
              name: provider.credentials.name,
              namespace: provider.credentials.namespace,
            },
          }
        ),
      },
    ]
    +
    controllerConf
    +
    [
      providerSecret(provider.credentials),
      kube.Namespace(provider.connectionSecretNamespace),
    ],
  [if params.providers.exoscale.enabled then '10_provider_exoscale']:
    local provider = params.providers.exoscale;

    local controllerConf = controllerConfig('exoscale', provider.controllerConfig);
    [
      crossplane.Provider('exoscale') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
      crossplane.ProviderConfig('exoscale') {
        apiVersion: 'exoscale.crossplane.io/v1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
            apiSecretRef: {
              name: provider.credentials.name,
              namespace: provider.credentials.namespace,
            },
          }
        ),
      },
    ]
    +
    controllerConf
    +
    [
      providerSecret(provider.credentials),
      kube.Namespace(provider.connectionSecretNamespace),
    ],
  [if params.providers.kubernetes.enabled then '10_provider_kubernetes']:
    local provider = params.providers.kubernetes;

    local sa = kube.ServiceAccount(provider.controllerConfig.serviceAccountName) {
      metadata+: {
        namespace: provider.namespace,
      },
    };
    local role = kube.ClusterRole('crossplane:provider:provider-kubernetes:system:custom') {
      rules: [
        {
          apiGroups: [ 'kubernetes.crossplane.io' ],
          resources: [ '*' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ '', 'coordination.k8s.io' ],
          resources: [ 'secrets', 'configmaps', 'events', 'leases' ],
          verbs: [ '*' ],
        },
        {
          apiGroups: [ '' ],
          resources: [ 'namespaces' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'stackgres.io' ],
          resources: [ 'sginstanceprofiles', 'sgclusters', 'sgpgconfigs', 'sgobjectstorages' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'networking.k8s.io' ],
          resources: [ 'networkpolicies' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'appcat.vshn.io' ],
          resources: [ 'xobjectbuckets' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
      ],
    };
    local rolebinding = kube.ClusterRoleBinding('crossplane:provider:provider-kubernetes:system:custom') {
      roleRef_: role,
      subjects_: [ sa ],
    };


    local controllerConf = controllerConfig('kubernetes', provider.controllerConfig);

    [
      crossplane.Provider('kubernetes') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
    ]
    +
    controllerConf
    +
    [

      crossplane.ProviderConfig('kubernetes') {
        apiVersion: 'kubernetes.crossplane.io/v1alpha1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
          }
        ),
      },
      sa,
      role,
      rolebinding,
    ],
}
