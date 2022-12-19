// main template for appcat
local compositionHelpers = import 'lib/appcat-compositions.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';


local compositeClusterRoles(composite) =
  if std.get(composite, 'createDefaultRBACRoles', true) then
    [
      kube.ClusterRole('appcat:composite:%s:claim-view' % composite.metadata.name)
      {
        metadata+: {
          labels: {
            'rbac.authorization.k8s.io/aggregate-to-view': 'true',
          },
        },
        rules+: [
          {
            apiGroups: [ composite.spec.group ],
            resources: [
              composite.spec.claimNames.plural,
              '%s/status' % composite.spec.claimNames.plural,
              '%s/finalizers' % composite.spec.claimNames.plural,
            ],
            verbs: [ 'get', 'list', 'watch' ],
          },
        ],
      },
      kube.ClusterRole('appcat:composite:%s:claim-edit' % composite.metadata.name)
      {
        metadata+: {
          labels: {
            'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
            'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
          },
        },
        rules+: [
          {
            apiGroups: [ composite.spec.group ],
            resources: [
              composite.spec.claimNames.plural,
              '%s/status' % composite.spec.claimNames.plural,
              '%s/finalizers' % composite.spec.claimNames.plural,
            ],
            verbs: [ '*' ],
          },
        ],
      },
    ];

{
  CompositeClusterRoles(composite):
    compositeClusterRoles(composite),
}
