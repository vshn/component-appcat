local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local crossplane = import 'lib/appcat-crossplane.libsonnet';

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

local runtimeConfigRef(name) = {
  runtimeConfigRef: {
    name: name,
  },
};

local escapePackage(spec) =
  local img = std.split(spec.package, ':');

  {
    package: img[0] + ':' + std.strReplace(img[1], '/', '_'),
  };

// We define the rbacs here, so we don't have these ginormous yamls in the class
local providerRBAC = {
  kubernetes: {
    rules: [
      {
        apiGroups: [ 'kubernetes.crossplane.io' ],
        resources: [ '*' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'helm.crossplane.io' ],
        resources: [ 'releases' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ '', 'coordination.k8s.io' ],
        resources: [ 'secrets', 'configmaps', 'events', 'leases' ],
        verbs: [ '*' ],
      },
      {
        apiGroups: [ '' ],
        resources: [ 'namespaces', 'serviceaccounts', 'secrets', 'pods', 'pods/log', 'pods/portforward', 'pods/status', 'pods/attach', 'pods/exec', 'services' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
      },
      {
        apiGroups: [ 'apps' ],
        resources: [ 'statefulsets/scale' ],
        verbs: [ 'update', 'patch' ],
      },
      {
        apiGroups: [ 'apps' ],
        resources: [ 'statefulsets', 'deployments' ],
        verbs: [ 'get', 'delete', 'watch', 'list', 'patch', 'update', 'create' ],
      },
      {
        apiGroups: [ 'rbac.authorization.k8s.io' ],
        resources: [ 'clusterroles' ],
        resourceNames: [ 'appcat:services:read' ],
        verbs: [ 'bind' ],
      },
      {
        apiGroups: [ 'stackgres.io' ],
        resources: [ 'sginstanceprofiles', 'sgclusters', 'sgpgconfigs', 'sgobjectstorages', 'sgbackups', 'sgdbops', 'sgpoolconfigs' ],
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
      {
        apiGroups: [ 'vshn.appcat.vshn.io' ],
        resources: [ 'xvshnforgejoes', 'vshnforgejoes' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'vshn.appcat.vshn.io' ],
        resources: [ 'xvshnpostgresqls' ],
        verbs: [ 'get', 'update' ],
      },
      {
        apiGroups: [ 'cert-manager.io' ],
        resources: [ 'issuers', 'certificates' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'batch' ],
        resources: [ 'jobs', 'cronjobs' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'rbac.authorization.k8s.io' ],
        resources: [ 'clusterrolebindings', 'roles', 'rolebindings' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'vshn.appcat.vshn.io' ],
        resources: [ 'vshnpostgresqls' ],
        verbs: [ 'get', 'update' ],
      },
      {
        apiGroups: [ 'appcat.vshn.io' ],
        resources: [ 'objectbuckets' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'vshn.appcat.vshn.io' ],
        resources: [ 'vshnredis' ],
        verbs: [ 'get', 'update' ],
      },
      {
        apiGroups: [ 'monitoring.coreos.com' ],
        resources: [ 'prometheusrules', 'podmonitors', 'alertmanagerconfigs', 'servicemonitors' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'k8up.io' ],
        resources: [ 'schedules' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'k8up.io' ],
        resources: [ 'snapshots' ],
        verbs: [ 'get' ],
      },
      {
        apiGroups: [ 'minio.crossplane.io' ],
        resources: [ 'providerconfigs' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'appcat.vshn.io' ],
        resources: [ 'objectbuckets' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'postgresql.sql.crossplane.io' ],
        resources: [ 'providerconfigs' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'mysql.sql.crossplane.io' ],
        resources: [ 'providerconfigs' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'apiextensions.crossplane.io' ],
        resources: [ 'usages' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'policy' ],
        resources: [ 'poddisruptionbudgets' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'networking.k8s.io' ],
        resources: [ 'ingresses' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ '' ],
        resources: [ 'persistentvolumeclaims' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
      },
      {
        apiGroups: [ 'security.openshift.io' ],
        resources: [ 'securitycontextconstraints' ],
        verbs: [ 'use' ],
      },
      {
        apiGroups: [ 'apiextensions.crossplane.io' ],
        resources: [ 'compositionrevisions' ],
        verbs: [ 'get', 'list' ],
      },
      {
        apiGroups: [ 'vshn.appcat.vshn.io' ],
        resources: [ 'billingservices' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
      },
    ],
  },
  helm: {
    rules: [
      {
        apiGroups: [ 'extensions' ],
        resources: [ 'podsecuritypolicies' ],
        resourceNames: [ 'privileged' ],
        verbs: [ 'use' ],
      },
      {
        apiGroups: [ 'helm.crossplane.io' ],
        resources: [ '*' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ '' ],
        resources: [ 'namespaces', 'serviceaccounts', 'services', 'persistentvolumeclaims' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
      },
      {
        apiGroups: [ '' ],
        resources: [ 'pods' ],
        verbs: [ 'list', 'patch' ],
      },
      {
        apiGroups: [ 'apps' ],
        resources: [ 'statefulsets', 'deployments' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
      },
      {
        apiGroups: [ 'networking.k8s.io' ],
        resources: [ 'networkpolicies' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'batch' ],
        resources: [ 'jobs', 'cronjobs' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'delete', 'update', 'patch' ],
      },
      {
        apiGroups: [ 'monitoring.coreos.com' ],
        resources: [ 'servicemonitors' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'networking.k8s.io' ],
        resources: [ 'ingresses' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'policy' ],
        resources: [ 'poddisruptionbudgets' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'rbac.authorization.k8s.io' ],
        resources: [ 'roles', 'rolebindings', 'serviceaccounts' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'postgresql.cnpg.io' ],
        resources: [ 'clusters', 'imagecatalogs', 'scheduledbackups' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ 'monitoring.coreos.com' ],
        resources: [ 'prometheusrules', 'podmonitors', 'servicemonitors' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
    ],
  },
  minio: {
    rules: [
      {
        apiGroups: [ 'minio.crossplane.io' ],
        resources: [ '*' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
      {
        apiGroups: [ '' ],
        resources: [ 'secrets' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
    ],
  },
  sql: {
    rules: [
      {
        apiGroups: [ '' ],
        resources: [ 'secrets' ],
        verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
      },
    ],
  },
};

local additionalProviderConfigs(provider) =
  std.foldl(
    function(agg, config)
      agg + crossplane.ProviderConfig(config.name) {
        apiVersion: provider.apiVersion,
        spec+: config.spec,
      },
    provider.additionalProviderConfigs,
    {}
  );

local generateProviderConfigs(provider) =
  std.foldl(
    function(agg, config)
      agg + crossplane.ProviderConfig(config.name) {
        apiVersion: provider.apiVersion,
        spec+: {
          credentials: {
            secretRef: {
              key: 'kubeconfig',
              name: 'kubeconfig-' + config.name,
              namespace: params.crossplane.namespace,
            },
            source: 'Secret',
          },
        },
      },
    params.clusterManagementSystem.serviceClusterKubeconfigs,
    {}
  );

local provider(name, provider) =
  local sa = kube.ServiceAccount(provider.runtimeConfig.serviceAccountName) {
    metadata+: {
      namespace: provider.namespace,
    },
  };

  local runtimeConf = std.mergePatch(common.DefaultRuntimeConfigWithSaName(sa.metadata.name),
                                     if std.objectHas(provider, 'additionalRuntimeConfig') && provider.additionalRuntimeConfig != null then
                                       provider.additionalRuntimeConfig else {});

  local providerManifest = crossplane.Provider('provider-' + name) {
    spec+: escapePackage(provider.spec) + runtimeConfigRef(sa.metadata.name) + {
      packagePullPolicy: params.pullPolicy,
    },
  };

  local defaultConfig = crossplane.ProviderConfig(name) {
    apiVersion: provider.apiVersion,
    spec+: {
      credentials+: {
        source: 'InjectedIdentity',
      },
    } + provider.defaultProviderConfig,
  };

  local role = if std.objectHas(providerRBAC, name) then kube.ClusterRole('crossplane:provider:provider-' + name + ':system:custom') +
                                                         std.get(providerRBAC, name);

  local rolebinding = if std.objectHas(providerRBAC, name) then kube.ClusterRoleBinding('crossplane:provider:provider-' + name + ':system:custom') {
    roleRef_: role,
    subjects_: [ sa ],
  };

  local controlPlaneRolebinding = if std.objectHas(providerRBAC, name) then kube.ClusterRoleBinding('crossplane:provider:provider-' + name + ':control-plane') {
    roleRef_: role,
    subjects_: [ common.ControlPlaneSa ],
  };

  local providerName = 'provider-' + name;

  local metricsService =
    kube.Service(providerName + '-metrics') {
      metadata+: {
        namespace: 'syn-crossplane',
        labels+: {
          'app.kubernetes.io/name': providerName,
        },
      },
      spec+: {
        selector: {
          'pkg.crossplane.io/provider': providerName,
        },
        ports: [ {
          name: 'metrics',
          port: 8080,
        } ],
      },
    };
  local ServiceMonitor = kube._Object('monitoring.coreos.com/v1', 'ServiceMonitor', providerName) {
    metadata+: {
      namespace: 'syn-crossplane',
      labels+: {
        'app.kubernetes.io/name': providerName,
      },
    },
    spec: {
      endpoints: [ {
        port: 'metrics',
        path: '/metrics',
      } ],
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': providerName,
        },
      },
    },
  };

  {
    ['10_provider_%s' % name]:
      std.filter(
        function(elem) elem != null,
        [
          if vars.isSingleOrControlPlaneCluster then providerManifest,
          if vars.isSingleOrControlPlaneCluster then runtimeConf,
          if vars.isSingleOrControlPlaneCluster && std.objectHas(provider, 'defaultProviderConfig') then defaultConfig,
          if vars.isSingleOrControlPlaneCluster then sa,
          role,
          if vars.isSingleOrControlPlaneCluster then std.prune(metricsService),
          std.prune(ServiceMonitor),
          if vars.isSingleOrServiceCluster then controlPlaneRolebinding,
          if vars.isSingleOrControlPlaneCluster then rolebinding,
          if vars.isSingleOrControlPlaneCluster && std.objectHas(provider, 'credentials') then providerSecret(provider.credentials),
          if vars.isSingleOrControlPlaneCluster && std.objectHas(provider, 'connectionSecretNamespace') then kube.Namespace(provider.connectionSecretNamespace),
          if vars.isSingleOrControlPlaneCluster && std.objectHas(provider, 'additionalProviderConfigs') && std.length(provider.additionalProviderConfigs) > 0 then additionalProviderConfigs(provider),
          if vars.isSingleOrControlPlaneCluster && std.length(params.clusterManagementSystem.serviceClusterKubeconfigs) > 0 && (name == 'kubernetes' || name == 'helm') then generateProviderConfigs(provider),
        ]
      ),
  };

std.foldl(function(objOut, newObj) objOut + provider(newObj.name, newObj.value), std.filter(function(r) std.type(r.value) == 'object' && std.objectHas(r.value, 'enabled') && r.value.enabled, common.KeysAndValues(params.providers)), {})
