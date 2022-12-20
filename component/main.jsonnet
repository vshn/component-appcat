// main template for appcat
local compositionHelpers = import 'lib/appcat-compositions.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appcat;

local sync_options = {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      'argocd.argoproj.io/sync-wave': '10',
    },
  },
};

// https://syn.tools/syn/explanations/commodore-components/secrets.html
local secrets = std.filter(function(it) it != null, [
  if params.secrets[name] != null then
    local secret = params.secrets[name];
    assert std.objectHas(secret, 'metadata') : "missing `.metadata` in secret '%s'" % name;
    assert std.get(secret.metadata, 'namespace', '') != '' : "`.metadata.namespace` in secret '%s' cannot be empty" % name;
    kube.Secret(name) {} + com.makeMergeable(secret)
  for name in std.objectFields(params.secrets)
]);

local additionalResources = std.filter(function(it) it != null, [
  if params.additionalResources[name] != null then
    local res = params.additionalResources[name];
    kube._Object(res.apiVersion, res.kind, name) + com.makeMergeable(res)
  for name in std.objectFields(params.additionalResources)
]);

local composites = std.filter(function(it) it != null, [
  if params.composites[name] != null then
    local res = params.composites[name];
    kube._Object('apiextensions.crossplane.io/v1', 'CompositeResourceDefinition', name) + sync_options + com.makeMergeable(res)
  for name in std.objectFields(params.composites)
]);

local compositions = std.filter(function(it) it != null, [
  if params.compositions[name] != null then
    local composition = params.compositions[name];

    kube._Object('apiextensions.crossplane.io/v1', 'Composition', name) +
    sync_options +
    { spec+: com.makeMergeable(composition.spec) } +
    { metadata+: com.makeMergeable(std.get(composition, 'metadata', {})) } +
    {
      spec+: {
        patchSets+: if std.objectHas(composition, 'commonPatchSets') then [
          compositionHelpers.PatchSet(name)
          for name in std.objectFields(composition.commonPatchSets)
        ] else [],
        resources+: if std.objectHas(composition, 'commonResources') then [
          compositionHelpers.CommonResource(name)
          for name in std.objectFields(composition.commonResources)
        ] else [],
      },
    }

  for name in std.objectFields(params.compositions)
]);

local clusterRoles = std.flattenArrays(std.filter(function(it) it != null, [
  if params.composites[name] != null then
    local composite = params.composites[name];

    if std.get(composite, 'createDefaultRBACRoles', true) then
      [
        kube.ClusterRole('appcat:composite:%s:claim-view' % name)
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
        kube.ClusterRole('appcat:composite:%s:claim-edit' % name)
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
      ]

  for name in std.objectFields(params.composites)
]));

local xrdBrowseRole = kube.ClusterRole('appcat:browse') + {
  metadata+: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-view': 'true',
      'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
      'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    },
  },
  rules+: [
    {
      apiGroups: [ 'apiextensions.crossplane.io' ],
      resources: [
        'compositions',
        'compositionrevisions',
        'compositeresourcedefinitions',
      ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

// Define outputs below
{
  [if std.length(secrets) > 0 then 'secrets']: secrets,
  [if std.length(additionalResources) > 0 then 'additionalResources']: additionalResources,
  [if std.length(composites) > 0 then 'composites']: composites,
  [if std.length(compositions) > 0 then 'compositions']: compositions,
  [if std.length(clusterRoles) > 0 then 'clusterRoles']: clusterRoles + [ xrdBrowseRole ],
  '10_clusterrole_view': xrdBrowseRole,
}
