// main template for appcat
local compositionHelpers = import 'lib/appcat-compositions.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';


local common = import 'common.libsonnet';


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


local loadCRD(crd) = std.parseJson(kap.yaml_load('appcat/crds/%s' % crd));

local xrdFromCRD(name, crd, defaultComposition='', connectionSecretKeys=[]) =
  kube._Object('apiextensions.crossplane.io/v1', 'CompositeResourceDefinition', name) + common.SyncOptions + {
    spec: {
      claimNames: {
        kind: crd.spec.names.kind,
        plural: crd.spec.names.plural,
      },
      names: {
        kind: 'X%s' % crd.spec.names.kind,
        plural: 'x%s' % crd.spec.names.plural,
      },
      connectionSecretKeys: connectionSecretKeys,
      [if defaultComposition != '' then 'defaultCompositionRef']: {
        name: defaultComposition,
      },
      group: crd.spec.group,
      versions: crd.spec.versions,
    },
  };


{
  CompositeClusterRoles(composite):
    compositeClusterRoles(composite),
  LoadCRD(crd):
    loadCRD(crd),
  XRDFromCRD(name, crd, defaultComposition='', connectionSecretKeys=[]):
    xrdFromCRD(name, crd, defaultComposition=defaultComposition, connectionSecretKeys=connectionSecretKeys),
}
