local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/appcat-crossplane.libsonnet';

local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;

local controlNamespace = kube.Namespace(params.services.controlNamespace);

local maintenanceServiceAccount = kube.ServiceAccount('helm-based-service-maintenance') + {
  metadata+: {
    namespace: params.services.controlNamespace,
  },
};

local maintenanceRoleName = 'crossplane:appcat:job:helm:maintenance';
local maintenanceRole = kube.ClusterRole(maintenanceRoleName) {
  rules: [
    {
      apiGroups: [ 'helm.crossplane.io' ],
      resources: [ 'releases' ],
      verbs: [ 'patch', 'get', 'list', 'watch', 'update' ],
    },
    {
      apiGroups: [ 'apiextensions.crossplane.io' ],
      resources: [ 'compositionrevisions' ],
      verbs: [ 'get', 'list' ],
    },
    {
      apiGroups: [ 'vshn.appcat.vshn.io' ],
      resources: [ 'xvshnforgejoes', 'xvshnredis', 'xvshnkeycloaks', 'xvshnmariadbs', 'xvshnnextclouds', 'xvshnminios' ],
      verbs: [ 'get', 'update' ],
    },
  ],
};


local maintenanceClusterRoleBinding = kube.ClusterRoleBinding('crossplane:appcat:job:helm:maintenance') + {
  roleRef_: maintenanceRole,
  subjects_: [ maintenanceServiceAccount ],
};

local crossplaneEditMaintenanceBinding = kube.ClusterRoleBinding('crossplane:appcat:job:helm:crossplane:edit') + {
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'crossplane-edit',
  },
  subjects_: [ maintenanceServiceAccount ],
};

(if params.services.vshn.enabled && vars.isSingleOrServiceCluster then {
   '10_rbac_helm_service_maintenance_sa': maintenanceServiceAccount,
   '10_rbac_helm_service_maintenance_cluster_role': maintenanceRole,
   '10_rbac_helm_service_maintenance_cluster_role_binding': maintenanceClusterRoleBinding,
   '10_rbac_helm_service_maintenance_crossplane_edit_rolebinding': crossplaneEditMaintenanceBinding,
 } else {})
+ {
  '10_namespace_vshn_control': controlNamespace,
}
