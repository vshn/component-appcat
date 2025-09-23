local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';
local vars = import 'config/vars.jsonnet';

local params = inv.parameters.appcat;
local srcImage = std.get(params.images, 'statefulset-resize-controller');
local imageTag = std.strReplace(srcImage.tag, '/', '_');
local image = srcImage.registry + '/' + srcImage.repository + ':' + imageTag;
local stsParams = params.stsResizer;

local loadManifest(manifest) =
  std.parseJson(kap.yaml_load(inv.parameters._base_directory + '/dependencies/appcat/manifests/statefulset-resize-controller/' + srcImage.tag + '/' + manifest));

local metadata(name) = {
  name: name,
  namespace: params.namespace,
};

local args = [
  '--inplace',
];

local saName = 'sts-resizer';
local roleName = 'appcat:controller:sts-resizer';
local role = loadManifest('config/rbac/role.yaml') + {
  metadata+: metadata(roleName),
};
local sa = loadManifest('config/rbac/service_account.yaml') + {
  metadata+: metadata(saName),
};

local binding = loadManifest('config/rbac/role_binding.yaml') + {
  metadata+: metadata(roleName),
  roleRef+: {
    name: roleName,
  },
  subjects: [
    {
      name: saName,
      namespace: params.namespace,
      kind: 'ServiceAccount',
    },
  ],
};

local deployment = loadManifest('config/manager/manager.yaml') + {
  metadata+: metadata('sts-resizer'),
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: saName,
        containers: [
          if c.name == 'manager' then
            c {
              image: image,
              args: args,
              resources+: stsParams.resources,
            }
          else
            c
          for c in super.containers
        ],
      },
    },
  },
};

local resizeServiceAccount = kube.ServiceAccount('sa-sts-deleter') + {
  metadata+: {
    namespace: params.services.controlNamespace,
  },
};

local resizeClusterRole = kube.ClusterRole('appcat:job:resizejob') {
  rules: [
    {
      apiGroups: [ 'helm.crossplane.io' ],
      resources: [ 'releases' ],
      verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'statefulsets' ],
      verbs: [ 'delete', 'get', 'watch', 'list', 'update', 'patch' ],
    },
    {
      apiGroups: [ 'helm.crossplane.io' ],
      resources: [ 'releases' ],
      verbs: [ 'update', 'get' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'pods' ],
      verbs: [ 'list', 'get', 'update', 'delete' ],
    },
  ],
};

local resizeClusterRoleBinding = kube.ClusterRoleBinding('appcat:job:resizejob') + {
  roleRef_: resizeClusterRole,
  subjects_: [ resizeServiceAccount ],
};


local secretReadRole = kube.Role('appcat:job:read-controlclustercredentials') {
  metadata+: { namespace: params.namespace },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      resourceNames: [ 'controlclustercredentials' ],
      verbs: [ 'get' ],
    },
  ],
};

local secretReadBinding = kube.RoleBinding('appcat:job:read-controlclustercredentials') + {
  metadata+: { namespace: params.namespace },
  roleRef_: secretReadRole,
  subjects_: [ resizeServiceAccount ],
};

local cpPatchReleasesCR = kube.ClusterRole('appcat:cp:patch-helm-releases') {
  rules: [
    {
      apiGroups: [ 'helm.crossplane.io' ],
      resources: [ 'releases' ],
      verbs: [ 'get', 'patch', 'update' ],
    },
  ],
};

local cpPatchReleasesCRB = kube.ClusterRoleBinding('appcat:cp:patch-helm-releases') + {
  roleRef_: cpPatchReleasesCR,
  subjects_: [
    kube.ServiceAccount('appcat-service-cluster') + { metadata+: { namespace: params.namespace } },
  ],
};

(if params.services.vshn.enabled &&
    (params.services.vshn.redis.enabled || params.services.vshn.mariadb.enabled) &&
    vars.isSingleOrServiceCluster then {
   'controllers/sts-resizer/10_role': role,
   'controllers/sts-resizer/10_sa': sa,
   'controllers/sts-resizer/10_binding': binding,
   'controllers/sts-resizer/10_deployment': deployment,
   'controllers/sts-resizer/20_rbac_resize_job': [
     resizeServiceAccount,
     resizeClusterRole,
     resizeClusterRoleBinding,
   ],
 } else {})
+ (if vars.isServiceCluster then {
     'controllers/sts-resizer/21_secret_read_role': secretReadRole,
     'controllers/sts-resizer/21_secret_read_binding': secretReadBinding,
   } else {})
+ (if vars.isControlPlane then {
     'controllers/sts-resizer/30_cp_patch_releases_clusterrole': cpPatchReleasesCR,
     'controllers/sts-resizer/30_cp_patch_releases_clusterrolebinding': cpPatchReleasesCRB,
   } else {})
