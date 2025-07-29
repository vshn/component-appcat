local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;

local e2eNs = kube.Namespace('appcat-e2e') + {
  metadata+: {
    labels+: {
      'appuio.io/organization': 'vshn',
    },
  },
};

local e2eSA = kube.ServiceAccount('github-ci') + {
  metadata+: {
    namespace: 'appcat-e2e',
    labels: {
      'appuio.io/organization': 'vshn',
    },
  },
};

local e2eRoleBinding = kube.RoleBinding('appcat-e2e') + {
  metadata+: {
    namespace: 'appcat-e2e',
  },
  roleRef_: kube.ClusterRole('admin'),
  subjects_: [ e2eSA ],
};

local e2eClusterRole = kube.ClusterRole('appcat:e2e') + {
  rules: [
    {
      apiGroups: [ 'networking.k8s.io' ],
      resources: [ 'ingresses' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'namespaces' ],
      verbs: [ 'delete' ],
    },
    {
      apiGroups: [ 'batch' ],
      resources: [ 'jobs', 'cronjobs', 'jobs/finalizers', 'cronjobs/finalizers' ],
      verbs: [ 'get', 'list', 'create', 'delete', 'update', 'watch' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'secrets', 'services' ],
      verbs: [ 'list', 'get' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'deployments', 'statefulsets' ],
      verbs: [ 'list', 'get', 'watch' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'pods', 'pods/portforward', 'pods/exec' ],
      verbs: [ 'get', 'list', 'create' ],
    },
    {
      apiGroups: [ 'api.appcat.vshn.io' ],
      resources: [ 'vshnkeycloakbackups', 'vshnpostgresbackups' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ 'stackgres.io' ],
      resources: [ 'sgbackups' ],
      verbs: [ 'create', 'get', 'list' ],
    },
  ],
};

local e2eClusterRoleBinding = kube.ClusterRoleBinding('appcat:e2e') {
  roleRef_: e2eClusterRole,
  subjects_: [ e2eSA ],
};

local e2eSAToken = kube.Secret('github-ci-secret') + {
  metadata+: {
    namespace: 'appcat-e2e',
    annotations+: {
      'kubernetes.io/service-account.name': 'github-ci',
      'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
    },
  },
  type: 'kubernetes.io/service-account-token',
};

local diffSA = kube.ServiceAccount('crossplane-diff') + {
  metadata+: {
    namespace: params.namespace,
    labels: {
      'appuio.io/organization': 'vshn',
    },
  },
};

local diffClusterRoleBindingManagedResources = kube.ClusterRoleBinding('appcat:render-diff:managed-resources') {
  roleRef: {
    // the clusterrole `crossplane-view` is managed by crossplane and has view
    // permissions on all installed managed resources.
    name: 'crossplane-view',
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
  },
  subjects_: [ diffSA ],
};

local diffClusterRole = kube.ClusterRole('appcat:render-diff:functions') + {
  rules: [
    {
      apiGroups: [ 'pkg.crossplane.io' ],
      resources: [ 'functions' ],
      verbs: [ 'get', 'list' ],
    },
  ],
};

local diffClusterRoleBindingFunctions = kube.ClusterRoleBinding('appcat:render-diff:functions') {
  roleRef_: diffClusterRole,
  subjects_: [ diffSA ],
};

local diffSAToken = kube.Secret('diff-token') + {
  metadata+: {
    namespace: params.namespace,
    annotations+: {
      'kubernetes.io/service-account.name': diffSA.metadata.name,
      'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
    },
  },
  type: 'kubernetes.io/service-account-token',
};

(if params.services.vshn.e2eTests then {
   '20_rbac_vshn_e2e_tests': [ e2eNs, e2eSA, e2eRoleBinding, e2eClusterRoleBinding, e2eClusterRole, e2eSAToken ],
 } else {}) +
(if params.services.enableDiffRBAC then {
   '20_rbac_vshn_render_diff': [ diffSA, diffClusterRoleBindingManagedResources, diffClusterRoleBindingFunctions, diffClusterRole, diffSAToken ],
 } else {})
