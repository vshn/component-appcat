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


{
  [if params.providers.cloudscale.enabled then '10_provider_cloudscale']:
    local provider = params.providers.cloudscale;
    [
      crossplane.Provider('cloudscale') {
        spec+: provider.spec,
      },
      crossplane.ProviderConfig('cloudscale') {
        apiVersion: 'cloudscale.crossplane.io/v1',
        spec+: addCredentials(
          provider.config,
          {
            source: 'InjectIdentity',
            apiTokenSecretRef: {
              name: provider.credentials.name,
              namespace: provider.credentials.namespace,
            },
          }
        ),
      },
      providerSecret(provider.credentials),
      kube.Namespace(provider.connectionSecretNamespace),
    ],
  [if params.providers.exoscale.enabled then '10_provider_exoscale']:
    local provider = params.providers.exoscale;
    [
      crossplane.Provider('exoscale') {
        spec+: provider.spec,
      },
      crossplane.ProviderConfig('exoscale') {
        apiVersion: 'exoscale.crossplane.io/v1',
        spec+: addCredentials(
          provider.config,
          {
            source: 'InjectIdentity',
            apiSecretRef: {
              name: provider.credentials.name,
              namespace: provider.credentials.namespace,
            },
          }
        ),
      },
      providerSecret(provider.credentials),
      kube.Namespace(provider.connectionSecretNamespace),
    ],
}
